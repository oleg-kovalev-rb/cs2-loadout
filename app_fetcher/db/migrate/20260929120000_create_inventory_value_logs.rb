class CreateInventoryValueLogs < ActiveRecord::Migration[7.2]
  def change
    create_table :inventory_value_logs do |t|
      t.string :steam_id, null: false
      t.date :log_date, null: false
      t.integer :total_value_cents, null: false

      t.timestamps
    end

    add_index :inventory_value_logs, [ :steam_id, :log_date ], unique: true
  end
end
