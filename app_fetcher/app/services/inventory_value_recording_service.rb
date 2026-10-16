# typed: strict

class InventoryValueRecordingService
  extend T::Sig

  class << self
    extend T::Sig

    sig { params(steam_id: String).returns(ServiceResult[InventoryValueLog]) }
    def call(steam_id)
      user_inventory = UserInventory.find_by(steam_id: steam_id)
      return skipped if user_inventory.nil?
      return skipped if unpriced_marketable?(user_inventory)

      total_value_cents = user_inventory.items.sum { |item| item.current_price_cents || 0 }

      InventoryValueLog.upsert_all(
        [ { steam_id: steam_id, log_date: Date.current, total_value_cents: total_value_cents } ],
        unique_by: [ :steam_id, :log_date ]
      )

      log = InventoryValueLog.find_by!(steam_id: steam_id, log_date: Date.current)
      ServiceResult[InventoryValueLog].new(status: ServiceResult::Status::Ok, data: log, error: nil)
    end

    private

    sig { returns(ServiceResult[InventoryValueLog]) }
    def skipped
      ServiceResult[InventoryValueLog].new(status: ServiceResult::Status::Skipped, data: nil, error: nil)
    end

    sig { params(user_inventory: UserInventory).returns(T::Boolean) }
    def unpriced_marketable?(user_inventory)
      user_inventory.items.marketable.where(current_price_cents: nil, price_unavailable: false).exists?
    end
  end
end
