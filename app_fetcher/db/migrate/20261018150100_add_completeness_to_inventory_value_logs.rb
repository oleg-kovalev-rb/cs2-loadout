class AddCompletenessToInventoryValueLogs < ActiveRecord::Migration[7.2]
  def change
    add_column :inventory_value_logs, :items_count, :integer
    add_column :inventory_value_logs, :pricable_items_count, :integer
    add_column :inventory_value_logs, :priced_items_count, :integer
  end
end
