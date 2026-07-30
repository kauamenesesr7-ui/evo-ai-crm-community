class AddPublicSigningTokenToContracts < ActiveRecord::Migration[7.1]
  def up
    add_column :contracts, :public_token, :string
    execute <<~SQL.squish
      UPDATE contracts
      SET public_token =
        replace(gen_random_uuid()::text, '-', '') ||
        replace(gen_random_uuid()::text, '-', '')
      WHERE public_token IS NULL
    SQL
    change_column_null :contracts, :public_token, false
    add_index :contracts, :public_token, unique: true
  end

  def down
    remove_column :contracts, :public_token
  end
end
