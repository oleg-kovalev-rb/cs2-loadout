# typed: strict

class UserInventory < ApplicationRecord
  extend T::Sig

  has_many :user_inventory_items, dependent: :destroy
  has_many :items, through: :user_inventory_items

  validates :steam_id, presence: true, uniqueness: true

  class << self
    extend T::Sig

    sig { params(steam_id: String, item_ids: T::Array[Integer]).void }
    def sync!(steam_id, item_ids)
      transaction do
        user_inventory = find_or_create_by!(steam_id: steam_id)
        user_inventory.touch

        UserInventoryItem.where(user_inventory_id: user_inventory.id).delete_all
        next if item_ids.empty?

        UserInventoryItem.insert_all(
          item_ids.map { |item_id| { user_inventory_id: user_inventory.id, item_id: item_id, created_at: Time.current, updated_at: Time.current } }
        )
      end
    end
  end
end
