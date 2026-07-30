class BusinessReminderDeliveryJob < ApplicationJob
  queue_as :default

  def perform(reminder_id, tenant_id)
    tenant = Tenant.find(tenant_id)
    return unless tenant.subscription_access?

    Current.tenant = tenant
    Current.tenant_id = tenant.id
    Current.account = tenant.account_payload

    reminder = BusinessReminder.find(reminder_id)
    return unless reminder.status == 'pending'

    if reminder.delivery_channel == 'whatsapp'
      conversation = reminder.contact&.conversations&.order(last_activity_at: :desc)&.first
      raise ActiveRecord::RecordNotFound, 'No WhatsApp conversation found for reminder contact' unless conversation

      content = [reminder.title, reminder.description].compact_blank.join("\n\n")
      Messages::MessageBuilder.new(nil, conversation, content: content, private: false).perform
    end

    reminder.update!(status: 'delivered', delivered_at: Time.current, last_error: nil)
  rescue StandardError => e
    reminder&.update_columns(status: 'failed', last_error: e.message, updated_at: Time.current)
    raise
  ensure
    Current.reset
  end
end
