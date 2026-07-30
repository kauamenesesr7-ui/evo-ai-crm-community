require 'digest'
require 'securerandom'

class Contract < ApplicationRecord
  STATUSES = %w[draft signed canceled].freeze

  belongs_to :tenant
  belongs_to :rental, optional: true
  belongs_to :contact, optional: true
  belongs_to :contract_template, optional: true

  validates :number, :title, :content, :issued_on, presence: true
  validates :number, uniqueness: { scope: :tenant_id }
  validates :source_external_id, uniqueness: { scope: :tenant_id }, allow_blank: true
  validates :status, inclusion: { in: STATUSES }

  before_validation :assign_number, :assign_public_token, on: :create
  before_save :seal_signature, if: :company_signature_data_changed?

  def sign_by_customer!(name:, document:, signature_data:, ip:, user_agent:)
    transaction do
      update!(
        customer_signer_name: name,
        customer_signer_document: document,
        customer_signature_data: signature_data,
        customer_signature_ip: ip,
        customer_signature_user_agent: user_agent,
        customer_signed_at: Time.current,
        customer_accepted: true
      )
      seal_document!
      save!
    end
  end

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

  def assign_public_token
    self.public_token ||= SecureRandom.hex(32)
  end

  def seal_signature
    return if company_signature_data.blank?

    self.signed_at ||= Time.current
    self.status = 'signed'
    self.document_hash = Digest::SHA256.hexdigest(
      [tenant_id, number, title, content, company_signature_data, signed_at.iso8601].join('|')
    )
  end

  def seal_document!
    signature_payload = [
      tenant_id, number, title, content, company_signature_data,
      customer_signature_data, customer_signer_name, customer_signer_document,
      customer_signed_at&.iso8601
    ].join('|')
    self.status = 'signed'
    self.signed_at ||= Time.current
    self.document_hash = Digest::SHA256.hexdigest(signature_payload)
  end
end
