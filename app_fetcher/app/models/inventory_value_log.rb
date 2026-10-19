# typed: strict

class InventoryValueLog < ApplicationRecord
  extend T::Sig

  validates :steam_id, presence: true
  validates :log_date, presence: true, uniqueness: { scope: :steam_id }
  validates :total_value_cents, presence: true, numericality: { greater_than_or_equal_to: 0 }
  validates :items_count, :pricable_items_count, :priced_items_count,
            numericality: { only_integer: true, greater_than_or_equal_to: 0 },
            allow_nil: true

  # Legacy rows (written before the completeness counters existed) were
  # gated on a fully priced inventory, so an absent counter means complete.
  sig { returns(T::Boolean) }
  def complete?
    pricable = pricable_items_count
    priced = priced_items_count
    return true if pricable.nil? || priced.nil?

    priced >= pricable
  end
end
