class CreateUsers < ActiveRecord::Migration[7.2]
  def change
    create_table :users do |t|
      t.string :steam_id, null: false
      t.string :nickname
      t.string :avatar_url

      t.timestamps
    end

    add_index :users, :steam_id, unique: true
  end
end
