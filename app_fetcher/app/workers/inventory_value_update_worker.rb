# typed: strict

class InventoryValueUpdateWorker
  include Sidekiq::Worker
  extend T::Sig

  sidekiq_options queue: :prices, retry: 5

  sig { params(steam_id: String).void }
  def perform(steam_id)
    client = Steam::Client.new
    response = client.fetch_user_inventory(steam_id)

    unless response.success?
      Rails.logger.warn("[InventoryValueUpdateWorker] Failed for #{steam_id}: #{response.error}")
      return
    end

    names = response.data.market_hash_names
    items = ItemPriceCache.fetch_for(names)
    total_value_cents = items.values.sum { |item| item.current_price_cents || 0 }

    InventoryValueLog.upsert_all(
      [ { steam_id: steam_id, log_date: Date.current, total_value_cents: total_value_cents } ],
      unique_by: [ :steam_id, :log_date ]
    )
  end
end
