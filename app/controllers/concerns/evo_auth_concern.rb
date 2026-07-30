require 'digest'
require 'base64'
require 'json'

module EvoAuthConcern
  extend ActiveSupport::Concern

  AUTH_VALIDATE_CACHE_TTL = 20.seconds

  private

  def authenticate_user_with_evo_auth(token, token_type)
    Current.evo_auth_validation_cache ||= {}
    cache_key = evo_auth_validation_cache_key(token, token_type)
    user_data = Current.evo_auth_validation_cache[cache_key]

    auth_service = EvoAuthService.new
    unless user_data
      store_key = evo_auth_validation_store_key(cache_key)
      user_data = Rails.cache.read(store_key)

      unless user_data
        user_data = auth_service.validate_token(token: token, token_type: token_type)
        ttl = auth_validation_cache_ttl(token, token_type)
        Rails.cache.write(store_key, user_data, expires_in: ttl) if ttl.positive?
      end
    end

    Current.evo_auth_validation_cache[cache_key] = user_data

    set_current_user_from_auth_data(user_data, token, token_type)
    true
  rescue EvoAuthService::ValidationError => e
    Rails.logger.warn "EvoAuth: Token validation failed: #{e.message}"
    error_code = e.code.presence || ApiErrorCodes::UNAUTHORIZED
    error_status = e.status.presence || :unauthorized
    error_response(error_code, e.message, status: error_status)
    false
  rescue EvoAuthService::AuthenticationError => e
    Rails.logger.error "EvoAuth: Authentication service error: #{e.message}"
    error_response(ApiErrorCodes::SERVICE_UNAVAILABLE, 'Authentication service unavailable', status: :service_unavailable)
    false
  end

  def bearer_token_present?
    request.headers['Authorization']&.start_with?('Bearer ')
  end

  def set_current_user_from_auth_data(user_data, token, token_type)
    auth_user = user_data['user'] || {}
    tenant_id = auth_user['tenant_id'] || user_data['tenant_id']
    tenant = resolve_local_tenant(user_data, tenant_id)
    raise EvoAuthService::ValidationError, 'Company not found' unless tenant
    unless tenant.subscription_access?
      raise EvoAuthService::ValidationError.new(
        'Subscription inactive',
        code: ApiErrorCodes::ACCOUNT_SUSPENDED,
        status: :payment_required
      )
    end

    Current.tenant = tenant
    Current.tenant_id = tenant.id
    Current.account = tenant.account_payload

    user = find_or_sync_local_user(auth_user, tenant.id)
    raise EvoAuthService::ValidationError, 'User not found locally' unless user

    # Set current user
    Current.user = user
    @current_user = user
    Current.authentication_method = token_type

    # Store role key from evo-auth for permission checks
    remote_role_key =
      user_data.dig('user', 'role', 'key') ||
      user_data.dig('role', 'key')
    local_role_keys = user.roles.pluck(:key)
    local_role_key =
      local_role_keys.find { |key| key.in?(Role::ADMIN_ROLE_KEYS) } ||
      local_role_keys.first
    role_key = remote_role_key.presence || local_role_key
    Current.evo_role_key = role_key

    # Resolve the granular `conversations.read_all` permission once per request and
    # cache it in Current. Admin short-circuits BEFORE any remote call. Non-admins
    # resolve via the remote evo-auth check (cached per request by the concern). The
    # model/policy/finder read this flag (mirroring how `administrator?` reads
    # `Current.evo_role_key`) — they never call the CRM `User#has_permission?` stub.
    Current.evo_can_read_all_inboxes =
      if user.administrator?
        true
      else
        has_user_permission?(user.id, 'conversations.read_all')
      end

    # Store tokens for downstream services
    if token_type == 'bearer'
      Current.bearer_token = token
    elsif token_type == 'api_access_token'
      Current.api_access_token = token
    end
  end

  def find_local_user(user_data, tenant_id)
    return nil unless user_data

    User.where(tenant_id: tenant_id).find_by(id: user_data['id']) ||
      User.where(tenant_id: tenant_id).find_by(email: user_data['email'])
  end

  # Auth and CRM can be upgraded independently. Existing community installations
  # already have CRM users/data before the auth service starts issuing tenant IDs,
  # and a short deployment window can therefore produce a valid token whose
  # company has not yet been mirrored in the CRM database. Prefer the tenant
  # already attached to the exact local user so upgrades keep their historical
  # inboxes. Brand-new accounts are provisioned from the signed auth response.
  def resolve_local_tenant(user_data, tenant_id)
    tenant = Tenant.unscoped.find_by(id: tenant_id)
    return tenant if tenant

    auth_user = user_data['user'] || {}
    local_user = User.unscoped.find_by(id: auth_user['id'])
    local_user ||= User.unscoped.find_by(email: auth_user['email'].to_s.downcase) if auth_user['email'].present?
    legacy_tenant = Tenant.unscoped.find_by(id: local_user&.tenant_id)

    if legacy_tenant
      Rails.logger.warn(
        "EvoAuth: reconciled missing auth company #{tenant_id} " \
        "to existing CRM company #{legacy_tenant.id} for user #{auth_user['id']}"
      )
      return legacy_tenant
    end

    provision_local_tenant(user_data, tenant_id)
  rescue ActiveRecord::RecordInvalid, ActiveRecord::RecordNotUnique => e
    Rails.logger.error "EvoAuth: failed to provision company #{tenant_id}: #{e.message}"
    Tenant.unscoped.find_by(id: tenant_id)
  end

  def provision_local_tenant(user_data, tenant_id)
    return nil if tenant_id.blank?

    account = Array(user_data['accounts']).find { |item| item['id'].to_s == tenant_id.to_s }
    account ||= Array(user_data['accounts']).first || {}
    auth_user = user_data['user'] || {}

    Tenant.unscoped.create_or_find_by!(id: tenant_id) do |record|
      record.name = account['name'].presence || auth_user['company_name'].presence || 'Minha empresa'
      record.slug = available_tenant_slug(account['slug'], record.name, tenant_id)
      record.domain = account['domain']
      record.support_email = account['support_email'].presence || auth_user['email']
      record.locale = account['locale'].presence || 'pt-BR'
      record.status = normalized_tenant_status(account['status'])
      record.subscription_status = normalized_subscription_status(account['subscription_status'])
      record.trial_ends_at = account['trial_ends_at']
      record.subscription_ends_at = account['subscription_ends_at']
      record.settings = account['settings'].presence || {}
      record.custom_attributes = account['custom_attributes'].presence || {}
    end
  end

  def available_tenant_slug(remote_slug, name, tenant_id)
    base = remote_slug.to_s.parameterize.presence || name.to_s.parameterize.presence || 'empresa'
    return base unless Tenant.unscoped.where(slug: base).where.not(id: tenant_id).exists?

    "#{base}-#{tenant_id.to_s.delete('-').first(8)}"
  end

  def normalized_tenant_status(status)
    Tenant.statuses.key?(status.to_s) ? status : 'active'
  end

  def normalized_subscription_status(status)
    Tenant.subscription_statuses.key?(status.to_s) ? status : 'active'
  end

  def find_or_sync_local_user(user_data, tenant_id)
    user = find_local_user(user_data, tenant_id)
    return user if user
    return nil if user_data.blank? || user_data['id'].blank? || user_data['email'].blank?

    User.unscoped.create_or_find_by!(id: user_data['id']) do |record|
      record.tenant_id = tenant_id
      record.name = user_data['name'].presence || user_data['email']
      record.display_name = user_data['display_name'].presence || record.name
      record.email = user_data['email'].to_s.downcase
      record.uid = record.email
      record.provider = user_data['provider'].presence || 'email'
      record.type = user_data['type'].presence || 'User'
      record.confirmed_at = user_data['confirmed_at'].presence || Time.current
    end
  rescue ActiveRecord::RecordInvalid, ActiveRecord::RecordNotUnique => e
    Rails.logger.error "EvoAuth: failed to sync user #{user_data['id']}: #{e.message}"
    find_local_user(user_data, tenant_id)
  end

  # Override current_user method to return our authenticated user
  def current_user
    @current_user || Current.user
  end

  def evo_auth_validation_cache_key(token, token_type)
    "#{token_type}:#{Digest::SHA256.hexdigest(token.to_s)}"
  end

  def evo_auth_validation_store_key(cache_key)
    "evo_auth:validate:#{cache_key}"
  end

  def auth_validation_cache_ttl(token, token_type)
    ttl = AUTH_VALIDATE_CACHE_TTL
    return ttl unless token_type.to_s == 'bearer'

    payload = decode_jwt_payload(token)
    return ttl unless payload.is_a?(Hash) && payload['exp'].present?

    remaining = payload['exp'].to_i - Time.now.to_i
    return 0.seconds if remaining <= 0

    [ttl, remaining.seconds].min
  rescue StandardError
    ttl
  end

  def decode_jwt_payload(token)
    segments = token.to_s.split('.')
    return {} if segments.length < 2

    payload_segment = segments[1]
    padding = '=' * ((4 - payload_segment.length % 4) % 4)
    decoded = Base64.urlsafe_decode64("#{payload_segment}#{padding}")
    JSON.parse(decoded)
  rescue StandardError
    {}
  end
end
