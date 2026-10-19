# typed: strict

class InventoryValueRecordingService < ApplicationService
  extend T::Sig

  BOOTSTRAP_MAX_WAIT = T.let(48.hours, ActiveSupport::Duration)

  class << self
    extend T::Sig

    sig { params(steam_id: String).returns(ApplicationService::Result[InventoryValueLog]) }
    def call(steam_id)
      user_inventory = UserInventory.find_by(steam_id: steam_id)
      return skipped if user_inventory.nil?

      snapshot = InventoryValueQuery.snapshot_for(user_inventory)
      return skipped if snapshot.pricable_items_count.positive? && snapshot.priced_items_count.zero?
      return skipped if waiting_for_first_prices?(user_inventory, snapshot)

      InventoryValueLog.upsert_all(
        [ snapshot_attributes(steam_id, snapshot) ],
        unique_by: [ :steam_id, :log_date ]
      )

      log = InventoryValueLog.find_by!(steam_id: steam_id, log_date: Date.current)
      success(log)
    end

    private

    sig { params(user_inventory: UserInventory, snapshot: InventoryValueQuery::ValueSnapshot).returns(T::Boolean) }
    def waiting_for_first_prices?(user_inventory, snapshot)
      return false unless bootstrap?(user_inventory)
      return false unless snapshot.pricable_items_count > snapshot.priced_items_count

      user_inventory.created_at > BOOTSTRAP_MAX_WAIT.ago
    end

    sig { params(user_inventory: UserInventory).returns(T::Boolean) }
    def bootstrap?(user_inventory)
      !InventoryValueLog.exists?(steam_id: user_inventory.steam_id)
    end

    sig { params(steam_id: String, snapshot: InventoryValueQuery::ValueSnapshot).returns(T::Hash[Symbol, T.untyped]) }
    def snapshot_attributes(steam_id, snapshot)
      {
        steam_id: steam_id,
        log_date: Date.current,
        total_value_cents: snapshot.total_value_cents,
        items_count: snapshot.items_count,
        pricable_items_count: snapshot.pricable_items_count,
        priced_items_count: snapshot.priced_items_count
      }
    end
  end
end
