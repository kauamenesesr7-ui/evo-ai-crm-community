class Api::V1::BusinessRemindersController < Api::V1::BusinessResourceController
  before_action :set_reminder, only: %i[show update destroy deliver dismiss]

  def index
    reminders = BusinessReminder.includes(:contact, :rental).chronological
    reminders = reminders.where(status: params[:status]) if params[:status].present?
    render_collection(reminders, message: 'Reminders retrieved successfully')
  end

  def show
    render_record(@reminder, message: 'Reminder retrieved successfully')
  end

  def create
    reminder = BusinessReminder.create!(reminder_params)
    BusinessReminderDeliveryJob.set(wait_until: reminder.remind_at).perform_later(reminder.id, Current.tenant_id) if reminder.delivery_channel == 'whatsapp'
    render_record(reminder, message: 'Reminder created successfully', status: :created)
  end

  def update
    @reminder.update!(reminder_params)
    render_record(@reminder, message: 'Reminder updated successfully')
  end

  def deliver
    BusinessReminderDeliveryJob.perform_later(@reminder.id, Current.tenant_id)
    render_record(@reminder, message: 'Reminder queued for delivery')
  end

  def dismiss
    @reminder.update!(status: 'dismissed')
    render_record(@reminder, message: 'Reminder dismissed')
  end

  def destroy
    @reminder.destroy!
    success_response(data: { id: @reminder.id }, message: 'Reminder deleted successfully')
  end

  private

  def set_reminder
    @reminder = BusinessReminder.find(params[:id])
  end

  def reminder_params
    params.require(:business_reminder).permit(
      :rental_id, :contact_id, :title, :description, :remind_at,
      :status, :delivery_channel, metadata: {}
    )
  end
end
