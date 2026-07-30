class ContractTemplate < ApplicationRecord
  belongs_to :tenant
  has_many :contracts, dependent: :nullify

  validates :name, :content, presence: true
  validates :version, numericality: { only_integer: true, greater_than: 0 }
  validates :name, uniqueness: { scope: %i[tenant_id version] }
  validates :source_external_id, uniqueness: { scope: :tenant_id }, allow_blank: true

  before_save :ensure_single_default, if: :is_default?

  def create_contract!(rental:, attributes: {})
    rendered_content = Contracts::TemplateRenderer.new(content, rental: rental).call
    tenant_settings = rental.tenant.settings || {}
    Contract.create!(
      {
        rental: rental,
        contact: rental.contact,
        contract_template: self,
        template_version: version,
        title: name,
        content: rendered_content,
        issued_on: Date.current,
        company_signature_data: tenant_settings['company_signature_data'],
        company_signer_name: tenant_settings['company_signer_name'],
        metadata: {
          'template_snapshot' => content,
          'rendered_snapshot' => rendered_content,
          'template_version' => version
        }
      }.merge(attributes)
    )
  end

  private

  def ensure_single_default
    self.class.where.not(id: id).where(is_default: true).update_all(is_default: false)
  end
end
