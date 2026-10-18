class AddPriceUpdatedAtToItems < ActiveRecord::Migration[7.2]
  def up
    add_column :items, :price_updated_at, :datetime

    execute <<~SQL.squish
      UPDATE items
      SET price_updated_at = updated_at
      WHERE current_price_cents IS NOT NULL
    SQL
  end

  def down
    remove_column :items, :price_updated_at
  end
end
