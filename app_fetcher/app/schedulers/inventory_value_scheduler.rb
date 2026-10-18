# typed: strict

class InventoryValueScheduler
  include Sidekiq::Worker
  extend T::Sig

  sidekiq_options queue: :default, retry: 3

  sig { void }
  def perform
    UserInventory.find_each do |user_inventory|
      InventoryValueUpdateWorker.perform_async(user_inventory.steam_id)
    end
  end
end
