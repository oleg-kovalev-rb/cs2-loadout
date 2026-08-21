class CreateItems < ActiveRecord::Migration[7.2]
  def change
    create_table :items do |t|
      t.string :market_hash_name, null: false
      t.jsonb :metadata, default: {}, null: false

      t.integer :current_price_cents
      t.integer :change_24h_cents

      t.timestamps
    end

    add_index :items, :market_hash_name, unique: true
    add_index :items, :metadata, using: :gin
  end
end
