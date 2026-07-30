class Api::V1::Public::ContractsController < ActionController::API
  before_action :set_contract

  def show
    render json: { success: true, data: public_payload }
  end

  def sign
    permitted = params.require(:contract).permit(
      :customer_signer_name,
      :customer_signer_document,
      :customer_signature_data,
      :customer_accepted
    )
    unless ActiveModel::Type::Boolean.new.cast(permitted[:customer_accepted])
      return render json: {
        success: false,
        error: { code: 'ACCEPTANCE_REQUIRED', message: 'É necessário aceitar o contrato' }
      }, status: :unprocessable_entity
    end
    if permitted[:customer_signer_name].blank? || permitted[:customer_signer_document].blank? ||
       permitted[:customer_signature_data].blank?
      return render json: {
        success: false,
        error: { code: 'SIGNATURE_REQUIRED', message: 'Nome, documento e assinatura são obrigatórios' }
      }, status: :unprocessable_entity
    end

    @contract.sign_by_customer!(
      name: permitted[:customer_signer_name],
      document: permitted[:customer_signer_document],
      signature_data: permitted[:customer_signature_data],
      ip: request.remote_ip,
      user_agent: request.user_agent
    )
    render json: { success: true, data: public_payload, message: 'Contrato assinado com sucesso' }
  end

  def pdf
    send_data(
      Contracts::PdfBuilder.new(@contract).call,
      filename: "#{@contract.number}.pdf",
      type: 'application/pdf',
      disposition: 'inline'
    )
  end

  private

  def set_contract
    @contract = Contract.unscoped.includes(:contact, :rental).find_by!(public_token: params[:token])
  rescue ActiveRecord::RecordNotFound
    render json: {
      success: false,
      error: { code: 'CONTRACT_NOT_FOUND', message: 'Contrato não encontrado' }
    }, status: :not_found
  end

  def public_payload
    {
      number: @contract.number,
      title: @contract.title,
      content: @contract.content,
      status: @contract.status,
      issued_on: @contract.issued_on,
      company_signer_name: @contract.company_signer_name,
      customer_signer_name: @contract.customer_signer_name,
      customer_signed_at: @contract.customer_signed_at,
      customer_accepted: @contract.customer_accepted,
      document_hash: @contract.document_hash,
      customer: @contract.contact&.name,
      event: @contract.rental&.title,
      event_date: @contract.rental&.starts_at
    }
  end
end
