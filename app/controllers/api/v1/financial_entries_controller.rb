class Api::V1::FinancialEntriesController < Api::V1::BusinessResourceController
  before_action :set_entry, only: %i[show update destroy mark_paid]

  def index
    entries = FinancialEntry.includes(:contact, :rental).due_first
    entries = entries.where(status: params[:status]) if params[:status].present?
    entries = entries.where(kind: params[:kind]) if params[:kind].present?
    entries = entries.where(due_on: Date.parse(params[:from])..) if params[:from].present?
    entries = entries.where(due_on: ..Date.parse(params[:to])) if params[:to].present?
    render_collection(entries, message: 'Financial entries retrieved successfully')
  end

  def show
    render_record(@entry, message: 'Financial entry retrieved successfully')
  end

  def create
    entry = FinancialEntry.create!(entry_params)
    render_record(entry, message: 'Financial entry created successfully', status: :created)
  end

  def update
    @entry.update!(entry_params)
    render_record(@entry, message: 'Financial entry updated successfully')
  end

  def mark_paid
    @entry.update!(status: 'paid', paid_on: params[:paid_on].presence || Date.current)
    render_record(@entry, message: 'Financial entry marked as paid')
  end

  def destroy
    @entry.destroy!
    success_response(data: { id: @entry.id }, message: 'Financial entry deleted successfully')
  end

  private

  def set_entry
    @entry = FinancialEntry.find(params[:id])
  end

  def entry_params
    params.require(:financial_entry).permit(
      :rental_id, :contact_id, :kind, :description, :category, :amount,
      :due_on, :paid_on, :status, :payment_method, :notes, metadata: {}
    )
  end
end
