# typed: strict

class InventoryListQuery
  extend T::Sig

  DEFAULT_PER_PAGE = T.let(24, Integer)

  class InventorySummary < T::Struct
    const :steam_id, String
    const :snapshot, InventoryValueQuery::ValueSnapshot
    const :delta, InventoryValueQuery::ValueDelta
    const :last_synced_at, Time
    const :rarity_counts, T::Hash[RarityTier, Integer]
  end

  class InventorySummaries < T::Struct
    const :inventories, T::Array[InventorySummary]
    const :pagination, Appliers::Pagination
    const :total_count, Integer
  end

  class << self
    extend T::Sig

    sig { params(params: ActionController::Parameters).returns(InventorySummaries) }
    def call(params)
      pagination = Appliers::Pagination.new(params[:page], params[:per_page], default_per_page: DEFAULT_PER_PAGE)

      scope = InventoryValueQuery.with_aggregates(
        UserInventory
          .left_joins(user_inventory_items: :item)
          .group("user_inventories.id")
          .select("user_inventories.id", "user_inventories.steam_id", "user_inventories.updated_at")
      )

      scope = Appliers::SortApplier.call(
        scope,
        params,
        enum_class: Options::InventorySortOption,
        default: Options::InventorySortOption::ValueDesc
      )

      inventories = pagination.apply(scope).to_a
      baselines = InventoryValueQuery.baseline_for(inventories.map(&:steam_id), Date.current - 1)
      rarity_counts = RarityBreakdownQuery.call(inventories.map(&:id))

      InventorySummaries.new(
        inventories: inventories.map do |inventory|
          summary_for(inventory, rarity_counts[inventory.id] || {}, baselines[inventory.steam_id])
        end,
        pagination: pagination,
        total_count: UserInventory.count
      )
    end

    private

    sig do
      params(
        inventory: UserInventory,
        rarity_counts: T::Hash[RarityTier, Integer],
        baseline: T.nilable(InventoryValueLog)
      ).returns(InventorySummary)
    end
    def summary_for(inventory, rarity_counts, baseline)
      snapshot = InventoryValueQuery.snapshot_from(inventory)

      InventorySummary.new(
        steam_id: inventory.steam_id,
        snapshot: snapshot,
        delta: InventoryValueQuery.delta_for(snapshot, baseline),
        last_synced_at: inventory.updated_at.to_time.utc,
        rarity_counts: rarity_counts
      )
    end
  end
end
