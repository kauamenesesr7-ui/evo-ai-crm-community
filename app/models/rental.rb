class Rental < ApplicationRecord
  STATUSES = %w[quote reserved confirmed completed canceled].freeze

  belongs_to :tenant
  belongs_to :contact, optional: true
  belongs_to :pipeline_item, optional: true
  has_many :rental_items, dependent: :destroy
  has_many :products, through: :rental_items
  has_many :financial_entries, dependent: :nullify
  has_many :business_reminders, dependent: :nullify
  has_many :contracts, dependent: :nullify

  validates :reference_code, :title, :starts_at, presence: true
  validates :reference_code, uniqueness: { scope: :tenant_id }
  validates :source_external_id, uniqueness: { scope: :tenant_id }, allow_blank: true
  validates :status, inclusion: { in: STATUSES }
  validates :total_amount, :paid_amount, numericality: { greater_than_or_equal_to: 0 }
  validates :guest_count, numericality: { greater_than_or_equal_to: 0, only_integer: true }, allow_nil: true
  validate :ends_after_start

  before_validation :assign_reference_code, on: :create

  scope :upcoming, -> { where(starts_at: Time.current..).order(:starts_at) }

  def outstanding_amount
    [total_amount - paid_amount, 0].max
  end

  private

  def assign_reference_code
    return if reference_code.present?

    prefix = Time.current.strftime('LOC-%Y%m')
    sequence = self.class.where('reference_code LIKE ?', "#{prefix}-%").count + 1
    self.reference_code = format('%<prefix>s-%<sequence>04d', prefix: prefix, sequence: sequence)
  end

  def ends_after_start
    return if ends_at.blank? || starts_at.blank? || ends_at >= starts_at

    errors.add(:ends_at, 'must be after the start date')
  end
end
