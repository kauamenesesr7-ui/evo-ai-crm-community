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
    record.as_json(include: associations)
  end
end
