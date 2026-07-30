class FinancialEntry < ApplicationRecord
  KINDS = %w[receivable payable].freeze
  STATUSES = %w[pending paid overdue canceled].freeze

  belongs_to :tenant
  belongs_to :rental, optional: true
  belongs_to :contact, optional: true

  validates :kind, inclusion: { in: KINDS }
  validates :status, inclusion: { in: STATUSES }
  validates :description, :due_on, presence: true
  validates :amount, numericality: { greater_than: 0 }

  before_validation :sync_paid_status

  scope :due_first, -> { order(:due_on, :created_at) }

  private

  def sync_paid_status
    self.status = 'paid' if paid_on.present?
    self.paid_on ||= Date.current if status == 'paid'
  end
end
