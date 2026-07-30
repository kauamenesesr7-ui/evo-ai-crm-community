class ImportExactLokagendaContractTemplate < ActiveRecord::Migration[7.1]
  ORIGINAL_TEMPLATE = <<~HTML.squish.freeze
    <div style="font-family: Arial, sans-serif; max-width: 800px; margin: 0 auto; padding: 40px; color: #333;">
      <div style="text-align: center; margin-bottom: 30px;">
        <h1 style="font-size: 24px; margin-bottom: 5px;">{{nome_empresa}}</h1>
        <p style="font-size: 14px; color: #666;">CNPJ/CPF: {{cnpj_empresa}} | Tel: {{telefone_empresa}}</p>
      </div>
      <h2 style="text-align: center; font-size: 20px; border-bottom: 2px solid #333; padding-bottom: 10px;"> CONTRATO DE LOCAÇÃO DE BRINQUEDOS E EQUIPAMENTOS </h2>
      <p style="margin-top: 20px; line-height: 1.8;"> Pelo presente instrumento particular, de um lado <strong>{{nome_empresa}}</strong>, inscrita no CNPJ/CPF sob o nº {{cnpj_empresa}}, doravante denominada <strong>LOCADORA</strong>, e de outro lado <strong>{{nome_cliente}}</strong>, inscrito(a) no CPF nº {{cpf_cliente}}, telefone {{telefone_cliente}}, e-mail {{email_cliente}}, doravante denominado(a) <strong>LOCATÁRIO(A)</strong>, têm entre si justo e contratado o que segue: </p>
      <h3 style="margin-top: 25px; font-size: 16px;">CLÁUSULA 1 - DO OBJETO</h3>
      <p style="line-height: 1.8;"> O presente contrato tem por objeto a locação dos seguintes itens: </p>
      <div style="margin: 15px 0; padding: 15px; background: #f9f9f9; border-radius: 5px;"> {{itens_locacao}} </div>
      <h3 style="margin-top: 25px; font-size: 16px;">CLÁUSULA 2 - DO EVENTO</h3>
      <p style="line-height: 1.8;"> Endereço do evento: <strong>{{endereco_evento}}</strong><br/> Data: <strong>{{data_evento}}</strong><br/> Montagem: <strong>{{horario_entrega}}</strong><br/> Desmontagem: <strong>{{horario_retirada}}</strong> </p>
      <h3 style="margin-top: 25px; font-size: 16px;">CLÁUSULA 3 - DO VALOR E PAGAMENTO</h3>
      <p style="line-height: 1.8;"> Valor total: <strong>{{valor_total}}</strong><br/> Desconto: <strong>{{valor_desconto}}</strong><br/> Valor pago (sinal): <strong>{{valor_pago}}</strong><br/> Valor restante: <strong>{{valor_restante}}</strong><br/> Frete/Deslocamento: <strong>{{valor_frete}}</strong><br/> Status: <strong>{{status_pagamento}}</strong> </p>
      <h3 style="margin-top: 25px; font-size: 16px;">CLÁUSULA 4 - DAS RESPONSABILIDADES DO LOCATÁRIO</h3>
      <p style="line-height: 1.8;"> O(A) LOCATÁRIO(A) se compromete a:<br/> a) Garantir espaço adequado e seguro para instalação dos equipamentos;<br/> b) Disponibilizar ponto de energia elétrica quando necessário;<br/> c) Não permitir uso indevido ou por pessoas não supervisionadas;<br/> d) Zelar pela integridade dos equipamentos durante todo o período de locação;<br/> e) Responsabilizar-se por danos causados por mau uso, vandalismo ou condições inadequadas;<br/> f) Não sublocar ou transferir os equipamentos a terceiros. </p>
      <h3 style="margin-top: 25px; font-size: 16px;">CLÁUSULA 5 - DAS RESPONSABILIDADES DA LOCADORA</h3>
      <p style="line-height: 1.8;"> A LOCADORA se compromete a:<br/> a) Entregar os equipamentos em perfeito estado de uso e funcionamento;<br/> b) Realizar montagem e desmontagem conforme combinado;<br/> c) Prestar orientações básicas de uso dos equipamentos;<br/> d) Cumprir os horários acordados, salvo casos de força maior. </p>
      <h3 style="margin-top: 25px; font-size: 16px;">CLÁUSULA 6 - DO CANCELAMENTO</h3>
      <p style="line-height: 1.8;"> Cancelamentos devem ser informados com antecedência mínima de 48 horas.<br/> Em caso de cancelamento fora do prazo, poderá ser retido até 50% do valor total como taxa compensatória.<br/> Em caso de condições climáticas adversas, poderá haver remarcação conforme disponibilidade. </p>
      <h3 style="margin-top: 25px; font-size: 16px;">CLÁUSULA 7 - DAS CONDIÇÕES GERAIS</h3>
      <p style="line-height: 1.8;"> a) A LOCADORA não se responsabiliza por acidentes decorrentes de mau uso dos equipamentos;<br/> b) O uso deve ser supervisionado por um responsável adulto;<br/> c) Qualquer dano será avaliado e cobrado do LOCATÁRIO;<br/> d) A montagem só será realizada em local adequado e seguro. </p>
      <h3 style="margin-top: 25px; font-size: 16px;">CLÁUSULA 8 - DO FORO</h3>
      <p style="line-height: 1.8;"> Fica eleito o foro da comarca da sede da LOCADORA para dirimir quaisquer dúvidas oriundas deste contrato. </p>
      <p style="margin-top: 30px; line-height: 1.8;"> E por estarem de acordo, firmam o presente contrato. </p>
      <p style="margin-top: 20px;">Data: {{data_atual}}</p>
      <div style="margin-top: 60px; display: flex; justify-content: space-between;">
        <div style="text-align: center; width: 45%;"><div style="border-top: 1px solid #333; padding-top: 10px;"><strong>LOCADORA</strong><br/> {{nome_empresa}}</div></div>
        <div style="text-align: center; width: 45%;"><div style="border-top: 1px solid #333; padding-top: 10px;"><strong>LOCATÁRIO(A)</strong><br/> {{nome_cliente}}</div></div>
      </div>
    </div>
  HTML

  def up
    ContractTemplate.reset_column_information

    Tenant.unscoped.find_each do |tenant|
      previous = ContractTemplate.unscoped
                                 .where(tenant_id: tenant.id, name: 'Contrato de locação padrão')
                                 .order(version: :desc)
                                 .first
      next if previous&.content == ORIGINAL_TEMPLATE

      ContractTemplate.unscoped.where(tenant_id: tenant.id, is_default: true)
                      .update_all(is_default: false, updated_at: Time.current)
      ContractTemplate.unscoped.create!(
        tenant_id: tenant.id,
        name: 'Contrato de locação padrão',
        content: ORIGINAL_TEMPLATE,
        version: (previous&.version || 0) + 1,
        is_default: true,
        metadata: { 'source' => 'LokAgenda', 'layout' => 'original' }
      )
    end
  end

  def down
    ContractTemplate.unscoped
                    .where("metadata ->> 'layout' = 'original'")
                    .delete_all
  end
end
