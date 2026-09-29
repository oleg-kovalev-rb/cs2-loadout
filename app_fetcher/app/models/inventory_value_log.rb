# typed: strict

class InventoryValueLog < ApplicationRecord
  extend T::Sig

  validates :steam_id, presence: true
  validates :log_date, presence: true, uniqueness: { scope: :steam_id }
  validates :total_value_cents, presence: true, numericality: { greater_than_or_equal_to: 0 }
end
