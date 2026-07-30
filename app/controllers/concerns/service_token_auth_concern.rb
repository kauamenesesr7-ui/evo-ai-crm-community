module ServiceTokenAuthConcern
  extend ActiveSupport::Concern

  private

  def service_token_present?
    service_token_from_header.present?
  end

  def service_token_from_header
    # Check for service token in multiple header formats
    request.headers['X-Service-Token'] ||
      request.headers['HTTP_X_SERVICE_TOKEN'] ||
      request.headers['X-Internal-API-Token'] ||
      request.headers['HTTP_X_INTERNAL_API_TOKEN']
  end

  def authenticate_service_token!
    Rails.logger.info "ServiceToken: Starting service token authentication"
    Rails.logger.info "ServiceToken: Token present? #{service_token_present?}"

    unless service_token_present?
      Rails.logger.warn "ServiceToken: No service token provided"
      render_service_token_unauthorized('Service token required for internal API access')
      return false
    end

    unless valid_service_token?
      Rails.logger.warn "ServiceToken: Invalid service token provided"
      render_service_token_unauthorized('Invalid service token')
      return false
    end

    Rails.logger.info "ServiceToken: Service token validation successful"
    set_service_authenticated_context
  end

  def valid_service_token?
    expected_token = ENV['EVOAI_CRM_API_TOKEN']
    provided_token = service_token_from_header

    return false if expected_token.blank? || provided_token.blank?

    # Use secure comparison to prevent timing attacks
    ActiveSupport::SecurityUtils.secure_compare(expected_token, provided_token)
  end

  def set_service_authenticated_context
    tenant_id = request.headers['X-Tenant-Id'] || request.headers['HTTP_X_TENANT_ID']
    tenant = Tenant.find_by(id: tenant_id)
    unless tenant&.subscription_access?
      render_service_token_unauthorized('Valid X-Tenant-Id header is required')
      return false
    end

    Current.tenant = tenant
    Current.tenant_id = tenant.id
    Current.account = tenant.account_payload
    # Set a flag to indicate this is a service-to-service call
    Current.service_authenticated = true
    Current.authentication_method = 'service_token'

    Rails.logger.info "ServiceToken: Set service authentication context"

    # For service-to-service calls, we might not have a specific user context
    # Instead, we operate with elevated privileges for internal operations
    true
  end

  def render_service_token_unauthorized(message = 'Unauthorized')
    render json: {
      error: message,
      code: 'SERVICE_TOKEN_UNAUTHORIZED',
      timestamp: Time.current.iso8601
    }, status: :unauthorized
  end

  def service_authenticated?
    Current.service_authenticated == true
  end
end
