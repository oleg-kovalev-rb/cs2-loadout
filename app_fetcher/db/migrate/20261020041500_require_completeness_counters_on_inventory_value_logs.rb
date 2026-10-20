class RequireCompletenessCountersOnInventoryValueLogs < ActiveRecord::Migration[7.2]
  def up
    change_column_null :inventory_value_logs, :items_count, false, 0
    change_column_null :inventory_value_logs, :pricable_items_count, false, 0
    change_column_null :inventory_value_logs, :priced_items_count, false, 0
  end

  def down
    change_column_null :inventory_value_logs, :items_count, true
    change_column_null :inventory_value_logs, :pricable_items_count, true
    change_column_null :inventory_value_logs, :priced_items_count, true
  end
end
