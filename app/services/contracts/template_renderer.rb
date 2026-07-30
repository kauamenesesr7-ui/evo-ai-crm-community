module Contracts
  class TemplateRenderer
    def initialize(template, rental:)
      @template = template
      @rental = rental
    end

    def call
      variables.reduce(template.to_s) do |content, (name, value)|
        content.gsub("{{#{name}}}", ERB::Util.html_escape(value.to_s))
      end
    end

    private

    attr_reader :template, :rental

    def variables
      contact = rental.contact
      tenant = rental.tenant
      settings = tenant.settings || {}
      paid = rental.paid_amount.to_d
      total = rental.total_amount.to_d

      {
        nome_empresa: tenant.name,
        cnpj_empresa: settings['tax_id'] || settings['cnpj'],
        telefone_empresa: settings['phone'],
        nome_cliente: contact&.name,
        cpf_cliente: contact&.tax_id,
        telefone_cliente: contact&.phone_number,
        email_cliente: contact&.email,
        itens_locacao: item_list,
        endereco_evento: rental.venue,
        data_evento: format_date(rental.starts_at),
        horario_entrega: format_time(rental.starts_at),
        horario_retirada: format_time(rental.ends_at),
        data_retirada: format_date(rental.ends_at),
        valor_total: currency(total),
        valor_desconto: currency(rental.metadata&.fetch('discount', 0)),
        valor_frete: currency(rental.metadata&.fetch('shipping', 0)),
        valor_pago: currency(paid),
        valor_restante: currency([total - paid, 0].max),
        status_pagamento: paid >= total && total.positive? ? 'Pago' : 'Pendente',
        data_pagamento_sinal: rental.metadata&.fetch('deposit_paid_on', nil),
        data_pagamento_total: rental.metadata&.fetch('paid_on', nil),
        data_atual: I18n.l(Date.current)
      }
    end

    def item_list
      rows = rental.rental_items.includes(:product).map do |item|
        "#{item.quantity}x #{item.product.name} — #{currency(item.subtotal)}"
      end
      rows = [rental.title] if rows.empty?
      rows.join('<br>')
    end

    def format_date(value)
      value.present? ? I18n.l(value.to_date) : ''
    end

    def format_time(value)
      value.present? ? I18n.l(value, format: :short).split.last : ''
    end

    def currency(value)
      ActionController::Base.helpers.number_to_currency(value.to_d, unit: 'R$ ', separator: ',', delimiter: '.')
    end
  end
end
