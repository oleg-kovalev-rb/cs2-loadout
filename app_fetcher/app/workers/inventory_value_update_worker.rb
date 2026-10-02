# typed: strict

class InventoryValueUpdateWorker
  include Sidekiq::Worker
  extend T::Sig

  sidekiq_options queue: :default, retry: 3

  sig { params(steam_id: String).void }
  def perform(steam_id)
    user_inventory = UserInventory.find_by(steam_id: steam_id)
    total_value_cents = user_inventory&.items&.sum { |item| item.current_price_cents || 0 } || 0

    InventoryValueLog.upsert_all(
      [ { steam_id: steam_id, log_date: Date.current, total_value_cents: total_value_cents } ],
      unique_by: [ :steam_id, :log_date ]
    )
  end
end
