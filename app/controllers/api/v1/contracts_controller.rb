class Api::V1::ContractsController < Api::V1::BusinessResourceController
  before_action :set_contract, only: %i[show update destroy sign customer_sign pdf]

  def index
    contracts = Contract.includes(:contact, :rental).order(issued_on: :desc, created_at: :desc)
    contracts = contracts.where(status: params[:status]) if params[:status].present?
    render_collection(contracts, message: 'Contracts retrieved successfully')
  end

  def show
    render_record(@contract, message: 'Contract retrieved successfully')
  end

  def create
    permitted = contract_params
    rental = Rental.find_by(id: permitted[:rental_id])
    template = ContractTemplate.find_by(id: permitted[:contract_template_id]) ||
               ContractTemplate.where(is_default: true).order(version: :desc).first

    contract = if rental && template && permitted[:content].blank?
                 template.create_contract!(
                   rental: rental,
                   attributes: permitted.except(
                     :rental_id, :contact_id, :contract_template_id, :content
                   ).to_h.compact_blank
                 )
               else
                 Contract.create!(permitted)
               end
    render_record(contract, message: 'Contract created successfully', status: :created)
  end

  def update
    @contract.update!(contract_params)
    render_record(@contract, message: 'Contract updated successfully')
  end

  def sign
    @contract.update!(signature_params)
    render_record(@contract, message: 'Contract signed by the company')
  end

  def customer_sign
    permitted = params.require(:contract).permit(
      :customer_signer_name, :customer_signer_document,
      :customer_signature_data, :customer_accepted
    )
    unless ActiveModel::Type::Boolean.new.cast(permitted[:customer_accepted])
      return error_response(
        ApiErrorCodes::VALIDATION_ERROR,
        'Contract acceptance is required',
        status: :unprocessable_entity
      )
    end

    @contract.sign_by_customer!(
      name: permitted[:customer_signer_name],
      document: permitted[:customer_signer_document],
      signature_data: permitted[:customer_signature_data],
      ip: request.remote_ip,
      user_agent: request.user_agent
    )
    render_record(@contract, message: 'Contract signed successfully')
  end

  def pdf
    send_data(
      Contracts::PdfBuilder.new(@contract).call,
      filename: "#{@contract.number}.pdf",
      type: 'application/pdf',
      disposition: 'inline'
    )
  end

  def destroy
    @contract.destroy!
    success_response(data: { id: @contract.id }, message: 'Contract deleted successfully')
  end

  private

  def set_contract
    @contract = Contract.find(params[:id])
  end

  def contract_params
    params.require(:contract).permit(
      :rental_id, :contact_id, :number, :title, :content, :status,
      :issued_on, :company_signer_name, :contract_template_id, metadata: {}
    )
  end

  def signature_params
    params.require(:contract).permit(:company_signature_data, :company_signer_name)
  end
end
