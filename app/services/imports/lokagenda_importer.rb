require 'open-uri'

module Imports
  class LokagendaImporter
    DEFAULT_TENANT_ID = '00000000-0000-4000-8000-000000000001'.freeze

    def initialize(payload, tenant_id: DEFAULT_TENANT_ID, dry_run: false)
      @payload = payload.deep_symbolize_keys
      @tenant_id = tenant_id
      @dry_run = dry_run
      @result = Hash.new(0)
      @products_by_source_id = {}
      @contacts_by_source_id = {}
      @rentals_by_source_id = {}
    end

    def call
      tenant = Tenant.unscoped.find(@tenant_id)
      Current.tenant = tenant
      Current.tenant_id = tenant.id

      ActiveRecord::Base.transaction do
        import_company(tenant)
        import_products
        import_contacts
        import_rentals
        import_contracts
        raise ActiveRecord::Rollback if @dry_run
      end

      @result.merge(dry_run: @dry_run)
    ensure
      Current.reset
    end

    private

    def import_company(tenant)
      company = @payload[:company]
      return if company.blank?

      settings = (tenant.settings || {}).deep_dup
      settings['business_profile'] = company.stringify_keys
      tenant.update!(
        name: company[:name].presence || tenant.name,
        support_email: company[:email].presence || tenant.support_email,
        settings: settings
      )
      @result[:companies] += 1
    end

    def import_products
      Array(@payload[:products]).each do |attributes|
        source_id = attributes.fetch(:source_id).to_s
        product = Product.find_or_initialize_by(sku: source_sku('PROD', source_id))
        created = product.new_record?
        product.assign_attributes(
          name: attributes.fetch(:name),
          description: attributes[:description],
          kind: 'physical',
          default_price: attributes[:price] || 0,
          currency: 'BRL',
          status: normalize_product_status(attributes[:status]),
          stock_quantity: attributes[:stock_quantity],
          metadata: (product.metadata || {}).merge(
            'source' => 'lokagenda',
            'source_id' => source_id,
            'track_stock' => attributes.fetch(:track_stock, true),
            'cost_price' => attributes[:cost_price]
          ).compact
        )
        product.save!
        attach_product_image(product, attributes[:image_url]) unless @dry_run
        @products_by_source_id[source_id] = product
        increment(:products, created)
      end
    end

    def import_contacts
      Array(@payload[:contacts]).each do |attributes|
        source_id = attributes.fetch(:source_id).to_s
        phone = normalize_phone(attributes[:phone])
        contact = Contact.find_by(phone_number: phone)
        contact ||= Contact.find_by(email: attributes[:email].to_s.downcase) if attributes[:email].present?
        contact ||= Contact.new
        created = contact.new_record?
        contact.skip_default_pipeline_assignment = true
        contact.assign_attributes(
          name: attributes.fetch(:name),
          phone_number: phone,
          email: attributes[:email].presence&.downcase,
          identifier: contact.identifier.presence || source_sku('CONT', source_id),
          type: 'person',
          location: attributes[:address].presence || attributes[:city].presence || contact.location,
          additional_attributes: (contact.additional_attributes || {}).merge(
            'source' => 'lokagenda',
            'source_id' => source_id,
            'city' => attributes[:city],
            'state' => attributes[:state]
          ).compact
        )
        contact.save!
        @contacts_by_source_id[source_id] = contact
        increment(:contacts, created)
      end
    end

    def import_rentals
      Array(@payload[:rentals]).each do |attributes|
        source_id = attributes.fetch(:source_id).to_s
        rental = Rental.find_or_initialize_by(reference_code: source_sku('LOC', source_id))
        created = rental.new_record?
        contact = @contacts_by_source_id[attributes[:contact_source_id].to_s]
        items = normalize_items(attributes[:items])
        rental.assign_attributes(
          contact: contact,
          title: attributes[:title].presence || "Evento de #{contact&.name || 'cliente'}",
          event_type: attributes[:event_type],
          starts_at: attributes.fetch(:starts_at),
          ends_at: attributes[:ends_at],
          venue: attributes[:venue],
          guest_count: attributes[:guest_count],
          status: normalize_rental_status(attributes[:status]),
          total_amount: attributes[:total_amount] || 0,
          paid_amount: attributes[:paid_amount] || 0,
          notes: attributes[:notes],
          metadata: (rental.metadata || {}).merge(
            'source' => 'lokagenda',
            'source_id' => source_id,
            'delivery_time' => attributes[:delivery_time],
            'pickup_time' => attributes[:pickup_time],
            'discount_amount' => attributes[:discount_amount],
            'shipping_amount' => attributes[:shipping_amount],
            'items' => items
          ).compact
        )
        rental.save!
        @rentals_by_source_id[source_id] = rental
        import_receivable(rental, contact, attributes)
        increment(:rentals, created)
      end
    end

    def import_receivable(rental, contact, attributes)
      amount = attributes[:total_amount].to_d - attributes.fetch(:paid_amount, 0).to_d
      return unless amount.positive?

      entry = FinancialEntry.find_or_initialize_by(
        rental: rental,
        description: "Locação #{rental.reference_code}"
      )
      created = entry.new_record?
      entry.assign_attributes(
        contact: contact,
        kind: 'receivable',
        category: 'Locações',
        amount: amount,
        due_on: Time.zone.parse(attributes.fetch(:starts_at).to_s).to_date,
        status: 'pending',
        notes: attributes[:notes],
        metadata: (entry.metadata || {}).merge(
          'source' => 'lokagenda',
          'source_id' => attributes.fetch(:source_id).to_s
        )
      )
      entry.save!
      increment(:financial_entries, created)
    end

    def import_contracts
      Array(@payload[:contracts]).each do |attributes|
        source_id = attributes.fetch(:source_id).to_s
        contract = Contract.find_or_initialize_by(number: source_sku('CTR', source_id))
        created = contract.new_record?
        rental = @rentals_by_source_id[attributes[:rental_source_id].to_s]
        contact = rental&.contact || @contacts_by_source_id[attributes[:contact_source_id].to_s]
        contract.assign_attributes(
          rental: rental,
          contact: contact,
          title: attributes.fetch(:title),
          content: attributes.fetch(:content),
          status: attributes[:status].presence || 'draft',
          issued_on: attributes[:issued_on].presence || Date.current,
          company_signer_name: attributes[:company_signer_name],
          metadata: (contract.metadata || {}).merge(
            'source' => 'lokagenda',
            'source_id' => source_id,
            'template' => attributes.fetch(:template, false)
          )
        )
        contract.save!
        increment(:contracts, created)
      end
    end

    def normalize_items(items)
      Array(items).map do |item|
        product = @products_by_source_id[item[:product_source_id].to_s]
        {
          'product_id' => product&.id,
          'product_source_id' => item[:product_source_id].to_s,
          'name' => item[:name].presence || product&.name,
          'unit_price' => item[:unit_price] || product&.default_price&.to_f || 0,
          'quantity' => item[:quantity] || 1
        }.compact
      end
    end

    def attach_product_image(product, image_url)
      return if image_url.blank? || product.images.attached?

      uri = URI.parse(image_url)
      raise ArgumentError, 'Product image URL must use HTTPS' unless uri.is_a?(URI::HTTPS)

      io = URI.open(uri, read_timeout: 20, open_timeout: 10)
      filename = File.basename(uri.path).presence || "#{product.sku}.jpg"
      product.images.attach(io: io, filename: filename)
    rescue OpenURI::HTTPError, SocketError, Timeout::Error => e
      Rails.logger.warn("[LokagendaImporter] image skipped for #{product.sku}: #{e.class}: #{e.message}")
      @result[:images_skipped] += 1
    end

    def normalize_phone(value)
      digits = value.to_s.gsub(/\D/, '')
      digits = "55#{digits}" if digits.length.between?(10, 11)
      digits.present? ? "+#{digits}" : nil
    end

    def normalize_product_status(value)
      value.to_s.in?(Product::STATUSES) ? value.to_s : 'active'
    end

    def normalize_rental_status(value)
      translations = {
        'pending' => 'quote',
        'approved' => 'reserved',
        'confirmed' => 'confirmed',
        'delivered' => 'completed',
        'returned' => 'completed',
        'cancelled' => 'canceled'
      }
      normalized = translations.fetch(value.to_s, value.to_s)
      normalized.in?(Rental::STATUSES) ? normalized : 'quote'
    end

    def source_sku(prefix, source_id)
      "LOK-#{prefix}-#{source_id.delete('-').first(12).upcase}"
    end

    def increment(resource, created)
      @result[created ? :"#{resource}_created" : :"#{resource}_updated"] += 1
    end
  end
end
