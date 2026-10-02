# typed: strict

class UserInventoryItem < ApplicationRecord
  belongs_to :user_inventory
  belongs_to :item
end
