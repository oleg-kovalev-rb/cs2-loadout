# typed: strict

class InventoryValueRecordingService
  extend T::Sig

  sig { params(steam_id: String).void }
  def initialize(steam_id)
    @steam_id = T.let(steam_id, String)
  end

  sig { returns(InventoryValueLog) }
  def call!
    user_inventory = UserInventory.find_by(steam_id: @steam_id)
    total_value_cents = user_inventory&.items&.sum { |item| item.current_price_cents || 0 } || 0

    InventoryValueLog.upsert_all(
      [ { steam_id: @steam_id, log_date: Date.current, total_value_cents: total_value_cents } ],
      unique_by: [ :steam_id, :log_date ]
    )

    InventoryValueLog.find_by!(steam_id: @steam_id, log_date: Date.current)
  end
end
