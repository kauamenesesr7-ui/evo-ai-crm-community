module Rentals
  class LifecycleService
    def initialize(rental, actor: Current.user)
      @rental = rental
      @actor = actor
    end

    def sync!
      Rental.transaction do
        validate_item_availability!
        sync_total!

        case rental.status
        when 'confirmed', 'completed'
          confirm_sale!
        when 'canceled'
          cancel_sale!
        else
          sync_open_opportunity!
        end

        rental.reload
      end
    end

    private

    attr_reader :rental, :actor

    def validate_item_availability!
      rental.rental_items.each(&:validate!)
    end

    def sync_total!
      return if rental.rental_items.empty?

      rental.update_column(:total_amount, rental.rental_items.sum(:subtotal))
    end

    def confirm_sale!
      item = ensure_pipeline_item!
      completed_stage = ensure_stage!(item.pipeline, :completed, 'Concluído', '#22C55E')

      sync_pipeline_products!(item)
      sync_services!(item)
      item.update!(pipeline_stage: completed_stage, completed_at: item.completed_at || Time.current)
      sync_receivable!
      ensure_contract!
    end

    def sync_open_opportunity!
      return unless rental.pipeline_item

      item = rental.pipeline_item
      active_stage = item.pipeline.pipeline_stages.stage_active.order(:position).first ||
                     ensure_stage!(item.pipeline, :active, 'Em atendimento', '#8B5CF6')
      sync_pipeline_products!(item)
      sync_services!(item)
      item.update!(pipeline_stage: active_stage, completed_at: nil)
      cancel_receivable!
    end

    def cancel_sale!
      if rental.pipeline_item
        cancelled_stage = ensure_stage!(rental.pipeline_item.pipeline, :cancelled, 'Cancelado', '#EF4444')
        rental.pipeline_item.update!(
          pipeline_stage: cancelled_stage,
          completed_at: rental.pipeline_item.completed_at || Time.current
        )
      end
      cancel_receivable!
      rental.contracts.where.not(status: 'signed').update_all(status: 'canceled')
    end

    def ensure_pipeline_item!
      return rental.pipeline_item if rental.pipeline_item

      pipeline = Pipeline.default.first || create_sales_pipeline!
      completed_stage = pipeline.pipeline_stages.stage_completed.order(:position).first ||
                        ensure_stage!(pipeline, :completed, 'Concluído', '#22C55E')
      item = PipelineItem.create!(
        pipeline: pipeline,
        pipeline_stage: completed_stage,
        contact: rental.contact,
        assigned_by: actor,
        entered_at: Time.current,
        completed_at: Time.current,
        custom_fields: rental_custom_fields
      )
      rental.update!(pipeline_item: item)
      item
    end

    def create_sales_pipeline!
      creator = actor || User.where(tenant_id: rental.tenant_id).order(:created_at).first
      pipeline = Pipeline.create!(
        name: 'Vendas e Locações',
        description: 'Funil integrado de eventos e locações',
        pipeline_type: 'sales',
        visibility: :public,
        is_active: true,
        is_default: true,
        created_by: creator
      )
      ensure_stage!(pipeline, :active, 'Em atendimento', '#8B5CF6', position: 1)
      ensure_stage!(pipeline, :completed, 'Concluído', '#22C55E', position: 2)
      ensure_stage!(pipeline, :cancelled, 'Cancelado', '#EF4444', position: 3)
      pipeline
    end

    def ensure_stage!(pipeline, type, name, color, position: nil)
      pipeline.pipeline_stages.public_send("stage_#{type}").first ||
        pipeline.pipeline_stages.create!(
          name: name,
          color: color,
          position: position || pipeline.pipeline_stages.maximum(:position).to_i + 1,
          stage_type: type
        )
    end

    def sync_pipeline_products!(item)
      desired_product_ids = rental.rental_items.pluck(:product_id)
      item.pipeline_item_products.where.not(product_id: desired_product_ids).destroy_all

      rental.rental_items.find_each do |rental_item|
        link = item.pipeline_item_products.find_or_initialize_by(product_id: rental_item.product_id)
        link.assign_attributes(
          quantity: rental_item.quantity,
          locked_unit_price: rental_item.locked_unit_price,
          currency: rental_item.currency,
          notes: "Locação #{rental.reference_code}",
          created_by_type: actor.present? ? 'User' : nil,
          created_by_id: actor&.id
        )
        link.save!
      end
    end

    def sync_services!(item)
      custom_fields = (item.custom_fields || {}).deep_dup
      custom_fields['currency'] = 'BRL'
      custom_fields['rental_id'] = rental.id
      custom_fields['rental_reference'] = rental.reference_code
      custom_fields['services'] = rental.rental_items.includes(:product).map do |rental_item|
        {
          'name' => rental_item.product.name,
          'value' => rental_item.subtotal.to_s,
          'product_id' => rental_item.product_id,
          'quantity' => rental_item.quantity
        }
      end
      custom_fields['services'] = [{ 'name' => rental.title, 'value' => rental.total_amount.to_s }] if custom_fields['services'].empty?
      item.update!(custom_fields: custom_fields)
    end

    def sync_receivable!
      entry = rental.financial_entries.receivable.find_or_initialize_by(
        source_external_id: "rental:#{rental.id}:receivable"
      )
      entry.assign_attributes(
        contact: rental.contact,
        description: "Locação #{rental.reference_code} — #{rental.title}",
        category: 'Locações',
        amount: rental.total_amount,
        due_on: rental.starts_at.to_date,
        status: rental.paid_amount >= rental.total_amount && rental.total_amount.positive? ? 'paid' : 'pending',
        paid_on: rental.paid_amount >= rental.total_amount && rental.total_amount.positive? ? Date.current : nil,
        metadata: { 'rental_reference' => rental.reference_code, 'paid_amount' => rental.paid_amount.to_s }
      )
      entry.save!
    end

    def cancel_receivable!
      rental.financial_entries.receivable.update_all(status: 'canceled')
    end

    def ensure_contract!
      contract = rental.contracts.order(created_at: :asc).first
      template = contract&.contract_template ||
                 ContractTemplate.where(is_default: true).order(version: :desc).first

      if contract
        render_draft_contract!(contract, template)
      else
        template&.create_contract!(rental: rental)
      end
    end

    def render_draft_contract!(contract, template)
      return if template.blank? || contract.status == 'signed'

      rendered_content = Contracts::TemplateRenderer.new(template.content, rental: rental).call
      metadata = (contract.metadata || {}).merge(
        'template_snapshot' => template.content,
        'rendered_snapshot' => rendered_content,
        'template_version' => template.version
      )
      contract.update!(
        contract_template: template,
        template_version: template.version,
        content: rendered_content,
        metadata: metadata
      )
    end

    def rental_custom_fields
      {
        'rental_id' => rental.id,
        'rental_reference' => rental.reference_code,
        'currency' => 'BRL'
      }
    end
  end
end
