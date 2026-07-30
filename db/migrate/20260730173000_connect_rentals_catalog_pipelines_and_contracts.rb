class ConnectRentalsCatalogPipelinesAndContracts < ActiveRecord::Migration[7.1]
  def change
    remove_index :pipelines, name: 'index_pipelines_on_is_default_unique',
                 if_exists: true
    add_index :pipelines, :tenant_id,
              unique: true,
              where: 'is_default = true',
              name: 'uniq_default_pipeline_per_tenant',
              if_not_exists: true

    add_column :products, :rental_category, :string, null: false, default: 'inflatable'
    add_column :products, :source_external_id, :string
    add_index :products, %i[tenant_id source_external_id],
              unique: true,
              where: 'source_external_id IS NOT NULL',
              name: 'uniq_products_tenant_source_external'
    add_check_constraint :products,
                         "rental_category IN ('inflatable', 'mobile_buffet')",
                         name: 'products_rental_category_check'

    add_column :rentals, :source_external_id, :string
    add_index :rentals, %i[tenant_id source_external_id],
              unique: true,
              where: 'source_external_id IS NOT NULL',
              name: 'uniq_rentals_tenant_source_external'

    create_table :rental_items, id: :uuid do |t|
      t.references :tenant, type: :uuid, null: false, foreign_key: true
      t.references :rental, type: :uuid, null: false, foreign_key: { on_delete: :cascade }
      t.references :product, type: :uuid, null: false, foreign_key: { on_delete: :restrict }
      t.integer :quantity, null: false, default: 1
      t.decimal :locked_unit_price, precision: 12, scale: 2, null: false
      t.decimal :subtotal, precision: 12, scale: 2, null: false
      t.string :currency, limit: 3, null: false, default: 'BRL'
      t.jsonb :metadata, null: false, default: {}
      t.timestamps
    end
    add_index :rental_items, %i[rental_id product_id], unique: true
    add_index :rental_items, %i[tenant_id product_id]
    add_check_constraint :rental_items, 'quantity > 0', name: 'rental_items_quantity_positive'
    add_check_constraint :rental_items, 'locked_unit_price >= 0', name: 'rental_items_price_non_negative'
    add_check_constraint :rental_items, 'subtotal >= 0', name: 'rental_items_subtotal_non_negative'

    create_table :contract_templates, id: :uuid do |t|
      t.references :tenant, type: :uuid, null: false, foreign_key: true
      t.string :name, null: false
      t.text :content, null: false
      t.integer :version, null: false, default: 1
      t.boolean :is_default, null: false, default: false
      t.string :source_external_id
      t.jsonb :metadata, null: false, default: {}
      t.timestamps
    end
    add_index :contract_templates, %i[tenant_id name version], unique: true,
              name: 'uniq_contract_templates_tenant_name_version'
    add_index :contract_templates, %i[tenant_id source_external_id],
              unique: true,
              where: 'source_external_id IS NOT NULL',
              name: 'uniq_contract_templates_tenant_source_external'
    add_index :contract_templates, :tenant_id,
              unique: true,
              where: 'is_default = true',
              name: 'uniq_default_contract_template_per_tenant'

    add_reference :contracts, :contract_template, type: :uuid, foreign_key: true
    add_column :contracts, :template_version, :integer
    add_column :contracts, :source_external_id, :string
    add_column :contracts, :customer_signer_name, :string
    add_column :contracts, :customer_signer_document, :string
    add_column :contracts, :customer_signature_data, :text
    add_column :contracts, :customer_signed_at, :datetime
    add_column :contracts, :customer_signature_ip, :inet
    add_column :contracts, :customer_signature_user_agent, :text
    add_column :contracts, :customer_accepted, :boolean, null: false, default: false
    add_index :contracts, %i[tenant_id source_external_id],
              unique: true,
              where: 'source_external_id IS NOT NULL',
              name: 'uniq_contracts_tenant_source_external'

    add_column :financial_entries, :source_external_id, :string
    add_index :financial_entries, %i[tenant_id source_external_id],
              unique: true,
              where: 'source_external_id IS NOT NULL',
              name: 'uniq_financial_entries_tenant_source_external'
  end
end
