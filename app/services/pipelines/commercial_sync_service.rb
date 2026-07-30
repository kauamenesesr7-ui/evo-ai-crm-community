module Pipelines
  class CommercialSyncService
    def self.cancel_for(pipeline_item_id, tenant_id:)
      FinancialEntry.unscoped
                    .where(tenant_id: tenant_id, pipeline_item_id: pipeline_item_id, kind: 'receivable')
                    .update_all(status: 'canceled', updated_at: Time.current)
    end

    def initialize(pipeline_item)
      @item = pipeline_item
    end

    def call
      return unless item&.persisted?
      return if Thread.current[guard_key]

      Thread.current[guard_key] = true
      begin
        with_tenant do
          ActiveRecord::Base.transaction do
            rental_reference.present? ? sync_rental_sale! : sync_standalone_sale!
          end
        end
      ensure
        Thread.current[guard_key] = false
      end
    end

    private

    attr_reader :item

    def guard_key
      :"pipeline_commercial_sync_#{item.id}"
    end

    def with_tenant
      previous_tenant_id = Current.tenant_id
      previous_tenant = Current.tenant
      Current.tenant_id = item.pipeline.tenant_id
      Current.tenant = Tenant.unscoped.find_by(id: Current.tenant_id)
      yield
    ensure
      Current.tenant_id = previous_tenant_id
      Current.tenant = previous_tenant
    end

    def rental_reference
      @rental_reference ||= item.custom_fields&.dig('rental_id').presence
    end

    def linked_rental
      @linked_rental ||= Rental.find_by(id: rental_reference)
    end

    def sync_rental_sale!
      unless linked_rental
        cancel_entry!
        return
      end

      desired_status = if item.pipeline_stage.stage_cancelled?
                         'canceled'
                       elsif item.pipeline_stage.stage_completed?
                         linked_rental.status == 'completed' ? 'completed' : 'confirmed'
                       else
                         'reserved'
                       end

      attributes = { status: desired_status }
      attributes[:total_amount] = item.commercial_value if item.commercial_value.positive?
      linked_rental.update!(attributes) if attributes.any? { |key, value| linked_rental.public_send(key) != value }
      Rentals::LifecycleService.new(linked_rental).sync!
    end

    def sync_standalone_sale!
      if item.counts_as_sale?
        entry = FinancialEntry.find_or_initialize_by(
          source_external_id: "pipeline_item:#{item.id}:receivable"
        )
        entry.assign_attributes(
          pipeline_item: item,
          contact: item.contact,
          kind: 'receivable',
          description: "Venda na pipeline — #{item.contact&.name || 'Contato'}",
          category: 'Vendas e locações',
          amount: item.commercial_value,
          due_on: event_date,
          status: entry.status == 'paid' ? 'paid' : 'pending',
          metadata: (entry.metadata || {}).merge(
            'pipeline_id' => item.pipeline_id,
            'pipeline_stage_id' => item.pipeline_stage_id
          )
        )
        entry.save!
      else
        cancel_entry!
      end
    end

    def cancel_entry!
      FinancialEntry.where(
        source_external_id: "pipeline_item:#{item.id}:receivable"
      ).update_all(status: 'canceled', updated_at: Time.current)
    end

    def event_date
      raw_date = item.custom_fields&.values_at('event_date', 'data_evento', 'starts_at')&.compact&.first
      raw_date.present? ? Date.parse(raw_date.to_s) : Date.current
    rescue Date::Error
      Date.current
    end
  end
end
