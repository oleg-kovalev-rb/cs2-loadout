class CreatePriceLogs < ActiveRecord::Migration[7.2]
  def change
    create_table :price_logs do |t|
      t.references :item, null: false, foreign_key: true
      
      t.integer :lowest_price_cents, default: 0, null: false
      t.integer :median_price_cents, default: 0, null: false
      t.integer :volume, default: 0, null: false

      t.timestamps
    end

    add_index :price_logs, [:item_id, :created_at]
  end
end
