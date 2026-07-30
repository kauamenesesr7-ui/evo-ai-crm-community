class Api::V1::ContractTemplatesController < Api::V1::BusinessResourceController
  before_action :set_template, only: %i[show update destroy]

  def index
    render_collection(
      ContractTemplate.order(is_default: :desc, name: :asc, version: :desc),
      message: 'Contract templates retrieved successfully'
    )
  end

  def show
    render_record(@template, message: 'Contract template retrieved successfully')
  end

  def create
    template = ContractTemplate.create!(template_params)
    render_record(template, message: 'Contract template created successfully', status: :created)
  end

  def update
    next_version = @template.class.create!(
      template_params.to_h.merge(
        name: template_params[:name].presence || @template.name,
        content: template_params[:content].presence || @template.content,
        version: @template.version + 1,
        source_external_id: nil
      )
    )
    render_record(next_version, message: 'New contract template version created successfully')
  end

  def destroy
    @template.destroy!
    success_response(data: { id: @template.id }, message: 'Contract template deleted successfully')
  end

  private

  def set_template
    @template = ContractTemplate.find(params[:id])
  end

  def template_params
    params.require(:contract_template).permit(
      :name, :content, :version, :is_default, :source_external_id, metadata: {}
    )
  end
end
