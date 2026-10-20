# typed: strict

class InventoryValueLog < ApplicationRecord
  extend T::Sig

  validates :steam_id, presence: true
  validates :log_date, presence: true, uniqueness: { scope: :steam_id }
  validates :total_value_cents, presence: true, numericality: { greater_than_or_equal_to: 0 }
  validates :items_count, :pricable_items_count, :priced_items_count,
            presence: true,
            numericality: { only_integer: true, greater_than_or_equal_to: 0 }

  sig { returns(T::Boolean) }
  def complete?
    priced_items_count >= pricable_items_count
  end
end
