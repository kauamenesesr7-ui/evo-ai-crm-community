require 'digest'

class Contract < ApplicationRecord
  STATUSES = %w[draft signed canceled].freeze

  belongs_to :tenant
  belongs_to :rental, optional: true
  belongs_to :contact, optional: true

  validates :number, :title, :content, :issued_on, presence: true
  validates :number, uniqueness: { scope: :tenant_id }
  validates :status, inclusion: { in: STATUSES }

  before_validation :assign_number, on: :create
  before_save :seal_signature, if: :company_signature_data_changed?

  def signed?
    status == 'signed' && signed_at.present? && document_hash.present?
  end

  private

  def assign_number
    return if number.present?

    prefix = Time.current.strftime('CTR-%Y')
    sequence = self.class.where('number LIKE ?', "#{prefix}-%").count + 1
    self.number = format('%<prefix>s-%<sequence>04d', prefix: prefix, sequence: sequence)
  end

  def seal_signature
    return if company_signature_data.blank?

    self.signed_at ||= Time.current
    self.status = 'signed'
    self.document_hash = Digest::SHA256.hexdigest(
      [tenant_id, number, title, content, company_signature_data, signed_at.iso8601].join('|')
    )
  end
end
