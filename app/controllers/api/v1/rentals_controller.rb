class Api::V1::RentalsController < Api::V1::BusinessResourceController
  before_action :set_rental, only: %i[show update destroy]

  def index
    rentals = Rental.includes(:contact, :pipeline_item, rental_items: :product).order(starts_at: :desc)
    rentals = rentals.where(status: params[:status]) if params[:status].present?
    rentals = rentals.where(starts_at: Time.zone.parse(params[:from])..) if params[:from].present?
    rentals = rentals.where(starts_at: ..Time.zone.parse(params[:to]).end_of_day) if params[:to].present?
    render_collection(rentals, message: 'Rentals retrieved successfully')
  end

  def show
    render_record(@rental, message: 'Rental retrieved successfully')
  end

  def create
    rental = Rental.transaction do
      record = Rental.create!(rental_params)
      sync_rental_items!(record)
      Rentals::LifecycleService.new(record).sync!
    end
    render_record(rental, message: 'Rental created successfully', status: :created)
  end

  def update
    Rental.transaction do
      @rental.update!(rental_params)
      sync_rental_items!(@rental) if params[:rental]&.key?(:items)
      Rentals::LifecycleService.new(@rental).sync!
    end
    render_record(@rental, message: 'Rental updated successfully')
  end

  def destroy
    Rental.transaction do
      pipeline_item = @rental.pipeline_item
      @rental.update!(status: 'canceled')
      Rentals::LifecycleService.new(@rental).sync!
      @rental.destroy!
      pipeline_item&.destroy!
    end
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

  def sync_rental_items!(rental)
    raw_items = Array(params.dig(:rental, :items))
    desired_product_ids = raw_items.filter_map { |item| item[:product_id].presence }
    rental.rental_items.where.not(product_id: desired_product_ids).destroy_all

    raw_items.each do |item|
      permitted = item.respond_to?(:permit) ? item.permit(:product_id, :quantity, :locked_unit_price, metadata: {}) : item
      product = Product.find(permitted[:product_id])
      rental_item = rental.rental_items.find_or_initialize_by(product: product)
      rental_item.assign_attributes(
        quantity: permitted[:quantity].presence || 1,
        locked_unit_price: permitted[:locked_unit_price].presence || product.default_price,
        currency: product.currency,
        metadata: permitted[:metadata] || {}
      )
      rental_item.save!
    end
  end
end
