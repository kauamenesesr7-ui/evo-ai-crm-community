class Api::V1::RentalsController < Api::V1::BusinessResourceController
  before_action :set_rental, only: %i[show update destroy]

  def index
    rentals = Rental.includes(:contact, :pipeline_item).order(starts_at: :desc)
    rentals = rentals.where(status: params[:status]) if params[:status].present?
    rentals = rentals.where(starts_at: Time.zone.parse(params[:from])..) if params[:from].present?
    rentals = rentals.where(starts_at: ..Time.zone.parse(params[:to]).end_of_day) if params[:to].present?
    render_collection(rentals, message: 'Rentals retrieved successfully')
  end

  def show
    render_record(@rental, message: 'Rental retrieved successfully')
  end

  def create
    rental = Rental.create!(rental_params)
    render_record(rental, message: 'Rental created successfully', status: :created)
  end

  def update
    @rental.update!(rental_params)
    render_record(@rental, message: 'Rental updated successfully')
  end

  def destroy
    @rental.destroy!
    success_response(data: { id: @rental.id }, message: 'Rental deleted successfully')
  end

  private

  def set_rental
    @rental = Rental.find(params[:id])
  end

  def rental_params
    params.require(:rental).permit(
      :contact_id, :pipeline_item_id, :reference_code, :title, :event_type,
      :starts_at, :ends_at, :venue, :guest_count, :status, :total_amount,
      :paid_amount, :notes, metadata: {}
    )
  end
end
