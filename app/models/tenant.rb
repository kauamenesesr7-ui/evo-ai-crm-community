class Tenant < ApplicationRecord
  self.table_name = 'tenants'

  has_many :users, dependent: :restrict_with_error
  has_many :rentals, dependent: :restrict_with_error
  has_many :financial_entries, dependent: :restrict_with_error
  has_many :business_reminders, dependent: :restrict_with_error
  has_many :contracts, dependent: :restrict_with_error

  enum :status, {
    active: 'active',
    suspended: 'suspended',
    archived: 'archived'
  }, prefix: true

  enum :subscription_status, {
    trialing: 'trialing',
    active: 'active',
    past_due: 'past_due',
    canceled: 'canceled',
    expired: 'expired'
  }, prefix: true

  def subscription_access?
    return false unless status_active?
    return true if subscription_status_active?
    return trial_ends_at.future? if subscription_status_trialing? && trial_ends_at.present?

    false
  end

  def account_payload
    {
      id: id,
      name: name,
      slug: slug,
      domain: domain,
      support_email: support_email,
      locale: locale,
      status: status,
      subscription_status: subscription_status,
      custom_attributes: custom_attributes || {},
      settings: settings || {}
    }
  end
end
