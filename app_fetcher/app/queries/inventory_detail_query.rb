# typed: strict

class InventoryDetailQuery
  extend T::Sig

  DEFAULT_TOP_ITEMS_PER_PAGE = T.let(12, Integer)

  class InventoryItems < T::Struct
    const :entries, T::Array[Item]
    const :pagination, Appliers::Pagination
    const :total_count, Integer
    const :trends, T::Hash[String, T::Array[ItemTrendCache::TrendPoint]]
  end

  class InventoryDetails < T::Struct
    const :steam_id, String
    const :last_synced_at, Time
    const :range, Options::DateRange
    const :value, InventoryValueQuery::InventoryValue
    const :items, InventoryItems
    const :avg_item_value_cents, Integer
    const :priciest_item, T.nilable(Item)
    const :rarity_counts, T::Hash[RarityTier, Integer]
  end

  class << self
    extend T::Sig

    sig { params(steam_id: String, params: ActionController::Parameters).returns(InventoryDetails) }
    def call(steam_id, params)
      user_inventory = UserInventory.find_by!(steam_id: steam_id)

      range = Options::DateRange::Param.new(
        allowed_ranges: InventoryValueQuery::SUPPORTED_RANGES,
        default: Options::DateRange::Last7Days,
        error_class: Api::Public::UnsupportedParamError
      ).parse(params[:period])

      top_items_pagination = Appliers::Pagination.new(
        params[:page], params[:per_page], default_per_page: DEFAULT_TOP_ITEMS_PER_PAGE
      )

      snapshot = InventoryValueQuery.snapshot_for(user_inventory)
      value = InventoryValueQuery::InventoryValue.new(
        snapshot: snapshot,
        history: InventoryValueQuery.history(steam_id, range, current: snapshot)
      )
      items_count = snapshot.items_count
      total_value_cents = snapshot.total_value_cents

      top_items = top_items_pagination.apply(
        Appliers::SortApplier.call(
          user_inventory.items,
          params,
          enum_class: Options::ItemSortOption,
          default: Options::ItemSortOption::PriceDesc,
          param_name: "sort"
        )
      ).to_a

      InventoryDetails.new(
        steam_id: steam_id,
        last_synced_at: user_inventory.updated_at.to_time.utc,
        range: range,
        value: value,
        items: InventoryItems.new(
          entries: top_items,
          pagination: top_items_pagination,
          total_count: items_count,
          trends: ItemTrendCache.fetch_for(top_items.map(&:market_hash_name))
        ),
        avg_item_value_cents: items_count.zero? ? 0 : total_value_cents / items_count,
        priciest_item: user_inventory.items.where.not(current_price_cents: nil).order(current_price_cents: :desc).first,
        rarity_counts: RarityBreakdownQuery.call([ user_inventory.id ]).fetch(user_inventory.id, {})
      )
    end
  end
end
