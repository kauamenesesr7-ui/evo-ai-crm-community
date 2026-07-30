class Api::V1::BusinessResourceController < Api::V1::BaseController
  private

  def render_collection(collection, message:)
    success_response(data: collection.map { |record| serialize_record(record) }, message: message)
  end

  def render_record(record, message:, status: :ok)
    success_response(data: serialize_record(record), message: message, status: status)
  end

  def serialize_record(record)
    associations = {}
    associations[:contact] = { only: %i[id name phone_number email] } if record.respond_to?(:contact)
    associations[:rental] = { only: %i[id reference_code title starts_at status] } if record.respond_to?(:rental)
    payload = record.as_json(include: associations)

    if record.is_a?(Rental)
      payload['items'] = record.rental_items.includes(:product).map do |item|
        item.as_json.merge('product' => ProductSerializer.serialize(item.product))
      end
      payload['outstanding_amount'] = record.outstanding_amount.to_f
      payload['pipeline_item'] = record.pipeline_item&.as_json(
        only: %i[id pipeline_id pipeline_stage_id completed_at]
      )
      payload['contracts'] = record.contracts.as_json(
        only: %i[id number title status issued_on signed_at document_hash]
      )
      payload['financial_entries'] = record.financial_entries.as_json(
        only: %i[id kind description amount due_on paid_on status payment_method]
      )
    elsif record.is_a?(Contract)
      payload['template'] = record.contract_template&.as_json(
        only: %i[id name version is_default]
      )
    end

    payload
  end
end
