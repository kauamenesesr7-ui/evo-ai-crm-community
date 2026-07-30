class ImportLokagendaBusinessData < ActiveRecord::Migration[7.1]
  TARGET_EMAIL = 'kauameneseslol@gmail.com'
  TEMPLATE_SOURCE_ID = '9224acb4-a7d7-48db-a996-b0309a7055eb'
  RENTAL_SOURCE_ID = '737bd311-f71e-47fe-ac7f-326c4e8e1da2'
  QUOTE_SOURCE_ID = 'a2e22423-a55c-40b1-9737-d635ce9f8833'

  CONTRACT_HTML = <<~HTML.freeze
    <h1 style="text-align:center">CONTRATO DE LOCAÇÃO DE BRINQUEDOS E EQUIPAMENTOS</h1>
    <p style="text-align:center"><strong>{{nome_empresa}}</strong><br>
    CNPJ: {{cnpj_empresa}} · Telefone: {{telefone_empresa}}</p>

    <p><strong>LOCADORA:</strong> {{nome_empresa}}, inscrita no CNPJ sob nº {{cnpj_empresa}},
    telefone {{telefone_empresa}}.</p>
    <p><strong>LOCATÁRIO(A):</strong> {{nome_cliente}}, CPF {{cpf_cliente}},
    telefone {{telefone_cliente}}, e-mail {{email_cliente}}.</p>

    <h2>CLÁUSULA 1ª — DO OBJETO</h2>
    <p>O presente contrato tem por objeto a locação dos brinquedos e equipamentos descritos abaixo:</p>
    <div>{{itens_locacao}}</div>

    <h2>CLÁUSULA 2ª — DO EVENTO, ENTREGA E RETIRADA</h2>
    <p>O evento será realizado em {{endereco_evento}}, na data {{data_evento}}.
    A montagem/entrega está prevista para {{horario_entrega}} e a desmontagem/retirada
    para {{horario_retirada}}, com retirada em {{data_retirada}} quando aplicável.</p>

    <h2>CLÁUSULA 3ª — DO VALOR E PAGAMENTO</h2>
    <p>Valor dos itens: {{valor_total}}. Desconto: {{valor_desconto}}.
    Frete: {{valor_frete}}. Valor pago: {{valor_pago}}.
    Saldo restante: {{valor_restante}}. Situação: {{status_pagamento}}.</p>
    <p>Data do pagamento do sinal: {{data_pagamento_sinal}}.
    Data do pagamento total: {{data_pagamento_total}}.</p>

    <h2>CLÁUSULA 4ª — DAS RESPONSABILIDADES DO LOCATÁRIO</h2>
    <p>O LOCATÁRIO compromete-se a utilizar os equipamentos de forma adequada,
    zelar pela integridade dos itens, respeitar as orientações de segurança,
    impedir uso indevido e comunicar imediatamente qualquer ocorrência.
    Danos decorrentes de mau uso poderão ser cobrados após avaliação.</p>

    <h2>CLÁUSULA 5ª — DAS RESPONSABILIDADES DA LOCADORA</h2>
    <p>A LOCADORA compromete-se a entregar os equipamentos em condições de uso,
    realizar montagem e desmontagem quando contratadas e orientar o LOCATÁRIO
    quanto à operação segura dos itens.</p>

    <h2>CLÁUSULA 6ª — DO CANCELAMENTO</h2>
    <p>O cancelamento deverá ser comunicado com antecedência mínima de 48 horas.
    Em cancelamentos fora desse prazo poderá ser retido até 50% do valor contratado.
    Em caso de condições climáticas que impeçam a utilização segura, as partes
    poderão remarcar o evento conforme disponibilidade.</p>

    <h2>CLÁUSULA 7ª — DAS CONDIÇÕES GERAIS</h2>
    <p>Qualquer alteração deverá ser acordada entre as partes. A tolerância quanto
    ao descumprimento de obrigação não implicará renúncia de direito.</p>

    <h2>CLÁUSULA 8ª — DO FORO</h2>
    <p>Fica eleito o foro do domicílio da LOCADORA para dirimir controvérsias
    decorrentes deste contrato, com renúncia a qualquer outro.</p>

    <p>Por estarem de acordo, as partes assinam o presente instrumento em {{data_atual}}.</p>
    <br>
    <table style="width:100%;text-align:center">
      <tr><td>_________________________________<br>LOCADORA — {{nome_empresa}}</td>
      <td>_________________________________<br>LOCATÁRIO(A) — {{nome_cliente}}</td></tr>
    </table>
  HTML

  PRODUCT_ROWS = [
    {
      source_external_id: 'lokagenda:product:touro-mecanico-teste',
      name: 'Touro Mecanico - TESTE',
      description: 'Touro Mecânico. Medidas: 5 x 5 metros. Necessita voltagem 220V.',
      default_price: 1_200,
      stock_quantity: 1,
      metadata: { dimensions: '5 x 5 metros', voltage: '220V', source: 'LokAgenda' }
    },
    {
      source_external_id: 'lokagenda:product:cama-elastica-305-teste',
      name: 'Cama Elástica 3,05mt TESTE',
      description: 'Medidas: 3,05 metros. Idade recomendada: até 10 anos.',
      default_price: 290,
      stock_quantity: 2,
      metadata: { dimensions: '3,05 metros', recommended_age: 'Até 10 anos', source: 'LokAgenda' }
    },
    {
      source_external_id: 'lokagenda:product:toboga-tigrao-teste',
      name: 'Tobogã Tigrão - TESTE',
      description: 'Tobogã. Medidas: A 4,20 x C 6,00 x L 4,00 metros.',
      default_price: 700,
      stock_quantity: 1,
      metadata: { dimensions: 'A 4,20 x C 6,00 x L 4,00 metros', source: 'LokAgenda' }
    }
  ].freeze

  def up
    user = select_one(<<~SQL.squish)
      SELECT id, tenant_id FROM users WHERE lower(email) = lower(#{quote(TARGET_EMAIL)}) LIMIT 1
    SQL
    return unless user

    tenant_id = user['tenant_id']
    now = quote(Time.current)

    PRODUCT_ROWS.each do |row|
      product_id = select_value(<<~SQL.squish)
        SELECT id FROM products
        WHERE tenant_id = #{quote(tenant_id)}
          AND (source_external_id = #{quote(row[:source_external_id])} OR name = #{quote(row[:name])})
        LIMIT 1
      SQL

      if product_id
        execute <<~SQL.squish
          UPDATE products SET
            source_external_id = #{quote(row[:source_external_id])},
            rental_category = 'inflatable',
            description = #{quote(row[:description])},
            default_price = #{row[:default_price]},
            stock_quantity = #{row[:stock_quantity]},
            kind = 'physical', currency = 'BRL', purchase_url = NULL, sku = NULL,
            metadata = #{quote(row[:metadata].to_json)}::jsonb,
            updated_at = #{now}
          WHERE id = #{quote(product_id)}
        SQL
      else
        execute <<~SQL.squish
          INSERT INTO products
            (id, tenant_id, name, kind, description, default_price, currency, status,
             stock_quantity, metadata, rental_category, source_external_id, created_at, updated_at)
          VALUES
            (gen_random_uuid(), #{quote(tenant_id)}, #{quote(row[:name])}, 'physical',
             #{quote(row[:description])}, #{row[:default_price]}, 'BRL', 'active',
             #{row[:stock_quantity]}, #{quote(row[:metadata].to_json)}::jsonb, 'inflatable',
             #{quote(row[:source_external_id])}, #{now}, #{now})
        SQL
      end
    end

    contact_id = select_value(<<~SQL.squish)
      SELECT id FROM contacts
      WHERE tenant_id = #{quote(tenant_id)}
        AND (lower(email) = 'leogaucho88@gmail.com' OR phone_number = '16991773037')
      LIMIT 1
    SQL
    unless contact_id
      contact_id = SecureRandom.uuid
      execute <<~SQL.squish
        INSERT INTO contacts
          (id, tenant_id, name, email, phone_number, identifier, type,
           additional_attributes, custom_attributes, blocked, created_at, updated_at)
        VALUES
          (#{quote(contact_id)}, #{quote(tenant_id)}, 'Leonardo flores',
           'leogaucho88@gmail.com', '16991773037', 'lokagenda:leonardo-flores', 'person',
           '{"source":"LokAgenda"}'::jsonb, '{}'::jsonb, false, #{now}, #{now})
      SQL
    end

    template_id = upsert_template!(tenant_id, now)
    rental_id = upsert_rental!(tenant_id, contact_id, now)
    upsert_rental_item!(tenant_id, rental_id, now)
    upsert_quote!(tenant_id, contact_id, now)
    upsert_contract!(tenant_id, contact_id, rental_id, template_id, now)
    sync_imported_sale!(tenant_id, rental_id)
  end

  def down
    raise ActiveRecord::IrreversibleMigration, 'Imported business data is retained for auditability'
  end

  private

  def upsert_template!(tenant_id, now)
    existing = select_value(<<~SQL.squish)
      SELECT id FROM contract_templates
      WHERE tenant_id = #{quote(tenant_id)} AND source_external_id = #{quote(TEMPLATE_SOURCE_ID)}
      LIMIT 1
    SQL
    return existing if existing

    id = SecureRandom.uuid
    execute <<~SQL.squish
      UPDATE contract_templates SET is_default = false WHERE tenant_id = #{quote(tenant_id)}
    SQL
    execute <<~SQL.squish
      INSERT INTO contract_templates
        (id, tenant_id, name, content, version, is_default, source_external_id, metadata, created_at, updated_at)
      VALUES
        (#{quote(id)}, #{quote(tenant_id)}, 'Contrato de locação padrão', #{quote(CONTRACT_HTML)},
         1, true, #{quote(TEMPLATE_SOURCE_ID)}, '{"source":"LokAgenda"}'::jsonb, #{now}, #{now})
    SQL
    id
  end

  def upsert_rental!(tenant_id, contact_id, now)
    existing = select_value(<<~SQL.squish)
      SELECT id FROM rentals
      WHERE tenant_id = #{quote(tenant_id)} AND source_external_id = #{quote(RENTAL_SOURCE_ID)}
      LIMIT 1
    SQL
    return existing if existing

    id = SecureRandom.uuid
    execute <<~SQL.squish
      INSERT INTO rentals
        (id, tenant_id, contact_id, reference_code, title, event_type, starts_at, ends_at,
         venue, status, total_amount, paid_amount, notes, metadata, source_external_id,
         created_at, updated_at)
      VALUES
        (#{quote(id)}, #{quote(tenant_id)}, #{quote(contact_id)}, 'LOC-202608-0001',
         'Locação Leonardo flores', 'Evento', '2026-08-06 12:00:00-03',
         '2026-08-06 16:00:00-03', 'Franca/SP', 'confirmed', 700, 0,
         'Entrega 12:00. Retirada 16:00. Pagamento via PIX.',
         '{"source":"LokAgenda","payment_method":"PIX"}'::jsonb, #{quote(RENTAL_SOURCE_ID)},
         #{now}, #{now})
    SQL
    id
  end

  def upsert_rental_item!(tenant_id, rental_id, now)
    product_id = select_value(<<~SQL.squish)
      SELECT id FROM products
      WHERE tenant_id = #{quote(tenant_id)}
        AND source_external_id = 'lokagenda:product:toboga-tigrao-teste'
      LIMIT 1
    SQL
    return unless product_id

    execute <<~SQL.squish
      INSERT INTO rental_items
        (id, tenant_id, rental_id, product_id, quantity, locked_unit_price,
         subtotal, currency, metadata, created_at, updated_at)
      VALUES
        (gen_random_uuid(), #{quote(tenant_id)}, #{quote(rental_id)}, #{quote(product_id)},
         1, 700, 700, 'BRL', '{"source":"LokAgenda"}'::jsonb, #{now}, #{now})
      ON CONFLICT (rental_id, product_id) DO UPDATE SET
        quantity = 1, locked_unit_price = 700, subtotal = 700, updated_at = EXCLUDED.updated_at
    SQL
  end

  def upsert_quote!(tenant_id, contact_id, now)
    return if select_value(<<~SQL.squish)
      SELECT id FROM rentals
      WHERE tenant_id = #{quote(tenant_id)} AND source_external_id = #{quote(QUOTE_SOURCE_ID)}
      LIMIT 1
    SQL

    execute <<~SQL.squish
      INSERT INTO rentals
        (id, tenant_id, contact_id, reference_code, title, event_type, starts_at,
         venue, status, total_amount, paid_amount, metadata, source_external_id,
         created_at, updated_at)
      VALUES
        (gen_random_uuid(), #{quote(tenant_id)}, #{quote(contact_id)}, 'ORC-202608-0001',
         'Orçamento Leonardo flores', 'Evento', '2026-08-06 12:00:00-03',
         'Franca/SP', 'quote', 715, 0,
         '{"source":"LokAgenda","original_status":"pending"}'::jsonb,
         #{quote(QUOTE_SOURCE_ID)}, #{now}, #{now})
    SQL
  end

  def upsert_contract!(tenant_id, contact_id, rental_id, template_id, now)
    source_id = "lokagenda:contract:#{RENTAL_SOURCE_ID}"
    return if select_value(<<~SQL.squish)
      SELECT id FROM contracts
      WHERE tenant_id = #{quote(tenant_id)} AND source_external_id = #{quote(source_id)}
      LIMIT 1
    SQL

    execute <<~SQL.squish
      INSERT INTO contracts
        (id, tenant_id, rental_id, contact_id, contract_template_id, template_version,
         number, title, content, status, issued_on, source_external_id, metadata,
         created_at, updated_at)
      VALUES
        (gen_random_uuid(), #{quote(tenant_id)}, #{quote(rental_id)}, #{quote(contact_id)},
         #{quote(template_id)}, 1, 'CTR-2026-0001', 'Contrato de locação padrão',
         #{quote(CONTRACT_HTML)}, 'draft', '2026-07-30', #{quote(source_id)},
         '{"source":"LokAgenda","template_source_id":"#{TEMPLATE_SOURCE_ID}"}'::jsonb,
         #{now}, #{now})
    SQL
  end

  def quote(value)
    connection.quote(value)
  end

  def sync_imported_sale!(tenant_id, rental_id)
    # ActiveRecord::Migration defines its own `Current` constant. Always use
    # the application-level request context explicitly inside migrations.
    previous_tenant_id = ::Current.tenant_id
    ::Current.tenant_id = tenant_id
    [Rental, RentalItem, Product, Contract, ContractTemplate, FinancialEntry].each(&:reset_column_information)
    rental = Rental.find(rental_id)
    contract = Contract.find_by(rental_id: rental.id)
    if contract&.contract_template
      rendered = Contracts::TemplateRenderer.new(contract.contract_template.content, rental: rental).call
      contract.update_columns(
        content: rendered,
        metadata: (contract.metadata || {}).merge(
          'template_snapshot' => contract.contract_template.content,
          'rendered_snapshot' => rendered,
          'template_version' => contract.contract_template.version
        ),
        updated_at: Time.current
      )
    end
    Rentals::LifecycleService.new(rental, actor: User.where(tenant_id: tenant_id).order(:created_at).first).sync!
  ensure
    ::Current.tenant_id = previous_tenant_id
  end
end
