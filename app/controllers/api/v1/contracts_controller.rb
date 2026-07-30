class Api::V1::ContractsController < Api::V1::BusinessResourceController
  before_action :set_contract, only: %i[show update destroy sign pdf]

  def index
    contracts = Contract.includes(:contact, :rental).order(issued_on: :desc, created_at: :desc)
    contracts = contracts.where(status: params[:status]) if params[:status].present?
    render_collection(contracts, message: 'Contracts retrieved successfully')
  end

  def show
    render_record(@contract, message: 'Contract retrieved successfully')
  end

  def create
    contract = Contract.create!(contract_params)
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
      :issued_on, :company_signer_name, metadata: {}
    )
  end

  def signature_params
    params.require(:contract).permit(:company_signature_data, :company_signer_name)
  end
end
