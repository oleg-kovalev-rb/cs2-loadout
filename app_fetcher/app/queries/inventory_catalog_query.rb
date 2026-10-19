# typed: strict

class InventoryCatalogQuery
  extend T::Sig

  DEFAULT_PER_PAGE = T.let(24, Integer)
  BASELINE_MAX_AGE_DAYS = T.let(2, Integer)

  AGGREGATE_COLUMNS = T.let(
    [
      "user_inventories.id",
      "user_inventories.steam_id",
      "user_inventories.updated_at"
    ] + InventoryValuation::AGGREGATE_COLUMNS,
    T::Array[String]
  )

  class InventorySummary < T::Struct
    const :steam_id, String
    const :items_count, Integer
    const :total_value_cents, Integer
    const :pricable_items_count, Integer
    const :priced_items_count, Integer
    const :oldest_price_at, T.nilable(Time)
    const :change_24h_cents, Integer
    const :change_basis_at, T.nilable(String)
    const :change_partial, T::Boolean
    const :change_available, T::Boolean
    const :last_synced_at, String
    const :rarity_counts, T::Hash[RarityTier, Integer]
  end

  class Page < T::Struct
    const :inventories, T::Array[InventorySummary]
    const :pagination, Appliers::Pagination
    const :total_count, Integer
  end

  class << self
    extend T::Sig

    sig { params(params: ActionController::Parameters).returns(Page) }
    def call(params)
      pagination = Appliers::Pagination.new(params[:page], params[:per_page], default_per_page: DEFAULT_PER_PAGE)

      scope = Appliers::SortApplier.call(
        UserInventory.left_joins(user_inventory_items: :item).group("user_inventories.id"),
        params,
        enum_class: Options::InventorySortOption,
        default: Options::InventorySortOption::ValueDesc
      )

      rows = pagination.apply(scope).pluck(AGGREGATE_COLUMNS.map { |column| Arel.sql(column) })
      rarity_counts_by_id = rarity_counts_for(rows.map { |row| row[0] })
      baselines = InventoryValuation.baseline_for(
        T.cast(rows.map { |row| row[1] }, T::Array[String]),
        Date.current - 1
      )

      Page.new(
        inventories: rows.map do |row|
          steam_id = T.cast(row[1], String)
          build_summary(row, rarity_counts_by_id[row[0]] || {}, baselines[steam_id])
        end,
        pagination: pagination,
        total_count: UserInventory.count
      )
    end

    private

    sig do
      params(
        row: T::Array[T.untyped],
        rarity_counts: T::Hash[RarityTier, Integer],
        baseline: T.nilable(InventoryValueLog)
      ).returns(InventorySummary)
    end
    def build_summary(row, rarity_counts, baseline)
      _id, steam_id, updated_at, *aggregate_values = row
      valuation = InventoryValuation.snapshot_from_row(aggregate_values)
      change, change_available, change_partial = change_for(valuation, baseline)

      InventorySummary.new(
        steam_id: T.cast(steam_id, String),
        items_count: valuation.items_count,
        total_value_cents: valuation.total_value_cents,
        pricable_items_count: valuation.pricable_items_count,
        priced_items_count: valuation.priced_items_count,
        oldest_price_at: valuation.oldest_price_at,
        change_24h_cents: change,
        change_basis_at: baseline&.log_date&.iso8601,
        change_partial: change_partial,
        change_available: change_available,
        last_synced_at: T.cast(updated_at, ActiveSupport::TimeWithZone).iso8601,
        rarity_counts: rarity_counts
      )
    end

    sig do
      params(
        valuation: InventoryValuation::Snapshot,
        baseline: T.nilable(InventoryValueLog)
      ).returns([ Integer, T::Boolean, T::Boolean ])
    end
    def change_for(valuation, baseline)
      return [ 0, false, !valuation.complete? ] if baseline.nil?

      change_partial = !valuation.complete? || !baseline.complete?
      available = baseline.log_date >= Date.current - BASELINE_MAX_AGE_DAYS
      return [ 0, false, change_partial ] unless available

      [ valuation.total_value_cents - baseline.total_value_cents, true, change_partial ]
    end

    sig { params(user_inventory_ids: T::Array[Integer]).returns(T::Hash[Integer, T::Hash[RarityTier, Integer]]) }
    def rarity_counts_for(user_inventory_ids)
      counts = T.let({}, T::Hash[Integer, T::Hash[RarityTier, Integer]])
      return counts if user_inventory_ids.empty?

      UserInventoryItem
        .joins(:item)
        .where(user_inventory_id: user_inventory_ids)
        .pluck(:user_inventory_id, "items.market_hash_name", Arel.sql("items.metadata ->> 'rarity'"))
        .each do |user_inventory_id, market_hash_name, rarity|
          tier = RarityTier.for_item(Item.new(market_hash_name: market_hash_name, metadata: { rarity: rarity }))
          next unless tier

          inventory_counts = (counts[user_inventory_id] ||= {})
          inventory_counts[tier] = (inventory_counts[tier] || 0) + 1
        end

      counts
    end
  end
end
