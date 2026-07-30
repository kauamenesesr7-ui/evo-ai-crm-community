class BusinessReminder < ApplicationRecord
  STATUSES = %w[pending delivered dismissed failed].freeze
  DELIVERY_CHANNELS = %w[internal whatsapp].freeze

  belongs_to :tenant
  belongs_to :rental, optional: true
  belongs_to :contact, optional: true

  validates :title, :remind_at, presence: true
  validates :status, inclusion: { in: STATUSES }
  validates :delivery_channel, inclusion: { in: DELIVERY_CHANNELS }

  scope :due, -> { where(status: 'pending', remind_at: ..Time.current) }
  scope :chronological, -> { order(:remind_at) }
end
