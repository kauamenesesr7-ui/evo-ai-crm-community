# frozen_string_literal: true

# ProductSerializer - Optimized serialization for Product resources.
#
# Plain Ruby module for Oj direct serialization, matching the convention
# used by CannedResponseSerializer / AutomationRuleSerializer in this app.
#
# Usage:
#   ProductSerializer.serialize(@product)
#   ProductSerializer.serialize_collection(@products)
module ProductSerializer
  extend self

  def serialize(product)
    {
      id: product.id,
      name: product.name,
      slug: product.slug,
      kind: 'physical',
      description: product.description,
      default_price: product.default_price.to_f,
      currency: product.currency,
      rental_category: product.rental_category,
      status: product.status,
      stock_quantity: product.stock_quantity,
      metadata: product.metadata || {},
      labels: product.respond_to?(:label_list) ? product.label_list : [],
      variants: [],
      images: serialize_images(product),
      created_at: product.created_at&.iso8601,
      updated_at: product.updated_at&.iso8601
    }
  end

  def serialize_collection(products)
    return [] unless products

    products.map { |product| serialize(product) }
  end

  private

  def serialize_images(product)
    return [] unless product.respond_to?(:images) && product.images.attached?

    product.images.map do |image|
      {
        id: image.id,
        url: Rails.application.routes.url_helpers.rails_blob_url(image, only_path: true),
        content_type: image.content_type,
        filename: image.filename.to_s,
        byte_size: image.byte_size
      }
    end
  end
end
