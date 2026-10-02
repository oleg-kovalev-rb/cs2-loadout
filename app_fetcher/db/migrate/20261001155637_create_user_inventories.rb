class CreateUserInventories < ActiveRecord::Migration[7.2]
  def change
    create_table :user_inventories do |t|
      t.string :steam_id, null: false

      t.timestamps
    end

    add_index :user_inventories, :steam_id, unique: true
  end
end
