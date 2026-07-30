class RentalItem < ApplicationRecord
  belongs_to :tenant
  belongs_to :rental
  belongs_to :product

  validates :quantity, numericality: { only_integer: true, greater_than: 0 }
  validates :locked_unit_price, :subtotal, numericality: { greater_than_or_equal_to: 0 }
  validates :currency, presence: true, length: { is: 3 }
  validates :product_id, uniqueness: { scope: :rental_id }
  validate :product_is_available_for_period

  before_validation :snapshot_product, on: :create
  before_validation :calculate_subtotal

  private

  def snapshot_product
    return unless product

    self.locked_unit_price ||= product.default_price
    self.currency ||= product.currency
  end

  def calculate_subtotal
    self.subtotal = quantity.to_i * locked_unit_price.to_d
  end

  def product_is_available_for_period
    return unless product && rental&.starts_at
    return unless rental.status.in?(%w[reserved confirmed])

    finish = rental.ends_at || rental.starts_at
    reserved_quantity = self.class
                        .joins(:rental)
                        .where(product_id: product_id, rentals: { status: %w[reserved confirmed] })
                        .where.not(rental_id: rental_id)
                        .where('rentals.starts_at <= ? AND COALESCE(rentals.ends_at, rentals.starts_at) >= ?',
                               finish, rental.starts_at)
                        .sum(:quantity)
    return if reserved_quantity + quantity.to_i <= product.stock_quantity.to_i

    errors.add(:quantity, "exceeds availability for #{product.name} in the selected period")
  end
end
