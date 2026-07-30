class CreateBusinessManagementTables < ActiveRecord::Migration[7.1]
  def change
    create_table :rentals, id: :uuid do |t|
      t.references :tenant, type: :uuid, null: false, foreign_key: true
      t.references :contact, type: :uuid, foreign_key: true
      t.references :pipeline_item, type: :uuid, foreign_key: true
      t.string :reference_code, null: false
      t.string :title, null: false
      t.string :event_type
      t.datetime :starts_at, null: false
      t.datetime :ends_at
      t.string :venue
      t.integer :guest_count
      t.string :status, null: false, default: 'quote'
      t.decimal :total_amount, precision: 12, scale: 2, null: false, default: 0
      t.decimal :paid_amount, precision: 12, scale: 2, null: false, default: 0
      t.text :notes
      t.jsonb :metadata, null: false, default: {}
      t.timestamps
    end
    add_index :rentals, %i[tenant_id reference_code], unique: true
    add_index :rentals, %i[tenant_id starts_at]
    add_index :rentals, %i[tenant_id status]

    create_table :financial_entries, id: :uuid do |t|
      t.references :tenant, type: :uuid, null: false, foreign_key: true
      t.references :rental, type: :uuid, foreign_key: true
      t.references :contact, type: :uuid, foreign_key: true
      t.string :kind, null: false, default: 'receivable'
      t.string :description, null: false
      t.string :category
      t.decimal :amount, precision: 12, scale: 2, null: false
      t.date :due_on, null: false
      t.date :paid_on
      t.string :status, null: false, default: 'pending'
      t.string :payment_method
      t.text :notes
      t.jsonb :metadata, null: false, default: {}
      t.timestamps
    end
    add_index :financial_entries, %i[tenant_id due_on]
    add_index :financial_entries, %i[tenant_id status]
    add_index :financial_entries, %i[tenant_id kind]

    create_table :business_reminders, id: :uuid do |t|
      t.references :tenant, type: :uuid, null: false, foreign_key: true
      t.references :rental, type: :uuid, foreign_key: true
      t.references :contact, type: :uuid, foreign_key: true
      t.string :title, null: false
      t.text :description
      t.datetime :remind_at, null: false
      t.string :status, null: false, default: 'pending'
      t.string :delivery_channel, null: false, default: 'internal'
      t.datetime :delivered_at
      t.text :last_error
      t.jsonb :metadata, null: false, default: {}
      t.timestamps
    end
    add_index :business_reminders, %i[tenant_id remind_at]
    add_index :business_reminders, %i[tenant_id status]

    create_table :contracts, id: :uuid do |t|
      t.references :tenant, type: :uuid, null: false, foreign_key: true
      t.references :rental, type: :uuid, foreign_key: true
      t.references :contact, type: :uuid, foreign_key: true
      t.string :number, null: false
      t.string :title, null: false
      t.text :content, null: false
      t.string :status, null: false, default: 'draft'
      t.date :issued_on, null: false
      t.datetime :signed_at
      t.text :company_signature_data
      t.string :company_signer_name
      t.string :document_hash
      t.jsonb :metadata, null: false, default: {}
      t.timestamps
    end
    add_index :contracts, %i[tenant_id number], unique: true
    add_index :contracts, %i[tenant_id status]
  end
end
