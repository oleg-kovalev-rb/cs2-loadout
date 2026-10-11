# typed: strict

class InventoryDetailQuery
  extend T::Sig

  DEFAULT_TOP_ITEMS_PER_PAGE = T.let(12, Integer)

  class HistoryPoint < T::Struct
    const :at, String
    const :total_value_cents, Integer
  end

  class Page < T::Struct
    const :steam_id, String
    const :last_synced_at, String
    const :range, PricePeriod
    const :total_value_cents, Integer
    const :change_cents, Integer
    const :change_percent, Float
    const :history, T::Array[HistoryPoint]
    const :items_count, Integer
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

      range = Appliers::SortApplier.call(
        params[:range], enum_class: PricePeriod, default: PricePeriod::SevenDays, param_name: "range"
      )
      items_sort_option = Appliers::SortApplier.call(
        params[:items_sort], enum_class: Options::ItemSortOption, default: Options::ItemSortOption::PriceDesc,
        param_name: "items_sort"
      )
      top_items_pagination = Appliers::Pagination.new(
        params[:items_page], params[:items_per_page], default_per_page: DEFAULT_TOP_ITEMS_PER_PAGE
      )

      items_count = user_inventory.items.count
      logs = InventoryValueLog.where(steam_id: steam_id).order(:log_date).to_a
      total_value_cents = logs.last&.total_value_cents || user_inventory.items.sum(:current_price_cents).to_i

      since = range.duration&.ago&.to_date
      logs_in_range = since ? logs.select { |log| log.log_date >= since } : logs
      change_cents, change_percent = change_for(logs_in_range)

      top_items = items_sort_option.apply(user_inventory.items)
                                    .limit(top_items_pagination.per_page)
                                    .offset(top_items_pagination.offset)
                                    .to_a

      Page.new(
        steam_id: steam_id,
        last_synced_at: user_inventory.updated_at.iso8601,
        range: range,
        total_value_cents: total_value_cents,
        change_cents: change_cents,
        change_percent: change_percent,
        history: logs_in_range.map { |log| HistoryPoint.new(at: log.created_at.iso8601, total_value_cents: log.total_value_cents) },
        items_count: items_count,
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

    sig { params(logs_in_range: T::Array[InventoryValueLog]).returns([ Integer, Float ]) }
    def change_for(logs_in_range)
      return [ 0, 0.0 ] if logs_in_range.size < 2

      base = T.must(logs_in_range.first).total_value_cents
      change = T.must(logs_in_range.last).total_value_cents - base
      percent = base.zero? ? 0.0 : (change.to_f / base * 100).round(2).to_f

      [ change, percent ]
    end

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
