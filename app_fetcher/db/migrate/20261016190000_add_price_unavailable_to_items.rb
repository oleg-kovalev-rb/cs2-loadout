class AddPriceUnavailableToItems < ActiveRecord::Migration[7.2]
  def change
    add_column :items, :price_unavailable, :boolean, default: false, null: false
  end
end
