# typed: strict

class InventoryDetailQuery
  extend T::Sig

  DEFAULT_TOP_ITEMS_PER_PAGE = T.let(12, Integer)

  class HistoryPoint < T::Struct
    const :at, String
    const :total_value_cents, Integer
    const :complete, T::Boolean
    const :priced_items_count, T.nilable(Integer)
    const :pricable_items_count, T.nilable(Integer)
  end

  class Page < T::Struct
    const :steam_id, String
    const :last_synced_at, String
    const :period, PricePeriod
    const :total_value_cents, Integer
    const :change_cents, Integer
    const :change_percent, Float
    const :change_basis_at, T.nilable(String)
    const :change_partial, T::Boolean
    const :change_available, T::Boolean
    const :history, T::Array[HistoryPoint]
    const :items_count, Integer
    const :pricable_items_count, Integer
    const :priced_items_count, Integer
    const :complete, T::Boolean
    const :oldest_price_at, T.nilable(Time)
    const :avg_item_value_cents, Integer
    const :priciest_item, T.nilable(Item)
    const :rarity_counts, T::Hash[RarityTier, Integer]
    const :top_items, T::Array[Item]
    const :top_items_pagination, Appliers::Pagination
    const :top_items_total_count, Integer
    const :trends, T::Hash[String, T::Array[ItemTrendCache::TrendPoint]]
  end

  class << self
    extend T::Sig

    sig { params(steam_id: String, params: ActionController::Parameters).returns(Page) }
    def call(steam_id, params)
      user_inventory = UserInventory.find_by!(steam_id: steam_id)

      period = PricePeriod.resolve(
        params[:period], supported: InventoryValueLog::SUPPORTED_PERIODS, default: PricePeriod::SevenDays
      )
      raise Api::Public::UnsupportedParamError, "Unsupported period: #{params[:period]}" unless period

      top_items_pagination = Appliers::Pagination.new(
        params[:page], params[:per_page], default_per_page: DEFAULT_TOP_ITEMS_PER_PAGE
      )

      valuation = InventoryValuation.current(user_inventory)
      series = InventoryValuation.series(steam_id, period, current: valuation)
      items_count = valuation.items_count
      total_value_cents = valuation.total_value_cents

      top_items = top_items_pagination.apply(
        Appliers::SortApplier.call(
          user_inventory.items,
          params,
          enum_class: Options::ItemSortOption,
          default: Options::ItemSortOption::PriceDesc,
          param_name: "sort"
        )
      ).to_a

      Page.new(
        steam_id: steam_id,
        last_synced_at: user_inventory.updated_at.iso8601,
        period: period,
        total_value_cents: total_value_cents,
        change_cents: series.change_cents,
        change_percent: series.change_percent,
        change_basis_at: series.change_basis_at,
        change_partial: series.change_partial,
        change_available: series.change_available,
        history: series.points.map do |point|
          HistoryPoint.new(
            at: point.at,
            total_value_cents: point.total_value_cents,
            complete: point.complete,
            priced_items_count: point.priced_items_count,
            pricable_items_count: point.pricable_items_count
          )
        end,
        items_count: items_count,
        pricable_items_count: valuation.pricable_items_count,
        priced_items_count: valuation.priced_items_count,
        complete: valuation.complete?,
        oldest_price_at: valuation.oldest_price_at,
        avg_item_value_cents: items_count.zero? ? 0 : total_value_cents / items_count,
        priciest_item: user_inventory.items.where.not(current_price_cents: nil).order(current_price_cents: :desc).first,
        rarity_counts: rarity_counts_for(user_inventory),
        top_items: top_items,
        top_items_pagination: top_items_pagination,
        top_items_total_count: items_count,
        trends: ItemTrendCache.fetch_for(top_items.map(&:market_hash_name))
      )
    end

    private

    sig { params(user_inventory: UserInventory).returns(T::Hash[RarityTier, Integer]) }
    def rarity_counts_for(user_inventory)
      counts = T.let({}, T::Hash[RarityTier, Integer])

      user_inventory.items.pluck(:market_hash_name, Arel.sql("items.metadata ->> 'rarity'")).each do |market_hash_name, rarity|
        tier = RarityTier.for_item(Item.new(market_hash_name: market_hash_name, metadata: { rarity: rarity }))
        next unless tier

        counts[tier] = (counts[tier] || 0) + 1
      end

      counts
    end
  end
end
