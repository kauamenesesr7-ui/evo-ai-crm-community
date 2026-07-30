module TenantScoped
  extend ActiveSupport::Concern

  included do
    default_scope do
      if Current.tenant_id.present? && column_names.include?('tenant_id')
        where(tenant_id: Current.tenant_id)
      else
        all
      end
    end

    before_validation :assign_current_tenant
    validate :tenant_matches_current
  end

  private

  def assign_current_tenant
    return unless has_attribute?(:tenant_id)

    self.tenant_id ||= Current.tenant_id
  end

  def tenant_matches_current
    return unless has_attribute?(:tenant_id)
    return if Current.tenant_id.blank? || tenant_id.blank?
    return if tenant_id.to_s == Current.tenant_id.to_s

    errors.add(:tenant_id, 'does not match the authenticated company')
  end
end
