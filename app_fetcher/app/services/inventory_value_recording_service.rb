# typed: strict

class InventoryValueRecordingService
  extend T::Sig

  BOOTSTRAP_MAX_WAIT = T.let(48.hours, ActiveSupport::Duration)

  class << self
    extend T::Sig

    sig { params(steam_id: String).returns(ServiceResult[InventoryValueLog]) }
    def call(steam_id)
      user_inventory = UserInventory.find_by(steam_id: steam_id)
      return skipped if user_inventory.nil?

      valuation = InventoryValuation.current(user_inventory)
      return skipped if valuation.pricable_items_count.positive? && valuation.priced_items_count.zero?
      return skipped if waiting_for_first_prices?(user_inventory, valuation)

      InventoryValueLog.upsert_all(
        [ snapshot_attributes(steam_id, valuation) ],
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

    sig { params(user_inventory: UserInventory, valuation: InventoryValuation::Snapshot).returns(T::Boolean) }
    def waiting_for_first_prices?(user_inventory, valuation)
      return false unless bootstrap?(user_inventory)
      return false unless valuation.pricable_items_count > valuation.priced_items_count

      user_inventory.created_at > BOOTSTRAP_MAX_WAIT.ago
    end

    sig { params(user_inventory: UserInventory).returns(T::Boolean) }
    def bootstrap?(user_inventory)
      !InventoryValueLog.exists?(steam_id: user_inventory.steam_id)
    end

    sig { params(steam_id: String, valuation: InventoryValuation::Snapshot).returns(T::Hash[Symbol, T.untyped]) }
    def snapshot_attributes(steam_id, valuation)
      {
        steam_id: steam_id,
        log_date: Date.current,
        total_value_cents: valuation.total_value_cents,
        items_count: valuation.items_count,
        pricable_items_count: valuation.pricable_items_count,
        priced_items_count: valuation.priced_items_count
      }
    end
  end
end
