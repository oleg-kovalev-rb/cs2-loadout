class CreateUserInventoryItems < ActiveRecord::Migration[7.2]
  def change
    create_table :user_inventory_items do |t|
      t.bigint :user_inventory_id, null: false
      t.bigint :item_id, null: false

      t.timestamps
    end

    add_index :user_inventory_items, [ :user_inventory_id, :item_id ], unique: true
    add_foreign_key :user_inventory_items, :user_inventories
    add_foreign_key :user_inventory_items, :items
  end
end
