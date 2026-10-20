# typed: strict

module Demo
  class Dataset
    extend T::Sig

    HISTORY_DAYS = T.let(Demo::PriceSeries::DAYS, Integer)

    sig { void }
    def initialize
      @series = T.let({}, T::Hash[String, Demo::PriceSeries])
      @items = T.let(nil, T.nilable(T::Array[Item]))
      @priced_items = T.let(nil, T.nilable(T::Hash[String, Item]))
      @portfolio_daily = T.let(nil, T.nilable(T::Array[Integer]))
    end

    sig { returns(T::Array[Item]) }
    def items
      @items ||= T.let(build_items, T.nilable(T::Array[Item]))
    end

    sig { returns(T::Hash[String, Item]) }
    def priced_items
      @priced_items ||= T.let(items.index_by(&:market_hash_name), T.nilable(T::Hash[String, Item]))
    end

    sig { returns(InventoryListQuery::InventorySummary) }
    def summary
      value = self.value(period: Options::DateRange::Last7Days.serialize)

      InventoryListQuery::InventorySummary.new(
        steam_id: "demo",
        snapshot: T.must(value.snapshot),
        delta: value.history.delta,
        last_synced_at: Time.current.to_time,
        rarity_counts: rarity_counts
      )
    end

    sig { params(period: T.nilable(String)).returns(InventoryValueQuery::InventoryValue) }
    def value(period: nil)
      range = parse_value_range(period)
      points = portfolio_points(range)
      snapshot = snapshot_for(points)

      InventoryValueQuery::InventoryValue.new(
        snapshot: snapshot,
        history: InventoryValueQuery::ValueHistory.new(
          points: points,
          delta: delta_for(points)
        )
      )
    end

    sig { params(params: ActionController::Parameters).returns(InventoryDetailQuery::InventoryDetails) }
    def details(params)
      range = parse_value_range(params[:period])
      pagination = Appliers::Pagination.new(
        params[:page],
        params[:per_page],
        default_per_page: InventoryDetailQuery::DEFAULT_TOP_ITEMS_PER_PAGE
      )
      entries = sort_items(params[:sort]).slice(pagination.offset, pagination.per_page) || []
      value = self.value(period: range.serialize)

      InventoryDetailQuery::InventoryDetails.new(
        steam_id: "demo",
        last_synced_at: Time.current.to_time,
        range: range,
        value: value,
        items: InventoryDetailQuery::InventoryItems.new(
          entries: entries,
          pagination: pagination,
          total_count: items.size,
          trends: trends_for(entries)
        ),
        avg_item_value_cents: items.empty? ? 0 : T.must(value.snapshot).total_value_cents / items.size,
        priciest_item: items.max_by { |item| item.current_price_cents || 0 },
        rarity_counts: rarity_counts
      )
    end

    sig { returns(T::Hash[String, T::Array[ItemTrendCache::TrendPoint]]) }
    def trends
      trends_for(items)
    end

    sig { params(market_hash_name: String).returns(Item) }
    def item!(market_hash_name)
      items.find { |item| item.market_hash_name == market_hash_name } ||
        raise(ActiveRecord::RecordNotFound, "Couldn't find demo item #{market_hash_name}")
    end

    sig do
      params(item: Item, period: T.nilable(String))
        .returns(ItemPriceHistoryQuery::ItemPriceHistory)
    end
    def history(item, period: nil)
      range = parse_history_range(period)
      points = series_for_item(item).points_for(range).map do |point|
        ItemPriceHistoryQuery::PricePoint.new(
          at: point.at,
          price_cents: point.price_cents,
          volume: point.volume
        )
      end

      ItemPriceHistoryQuery::ItemPriceHistory.new(range: range, points: points)
    end

    sig { params(items: T::Array[Item]).returns(T::Hash[RarityTier, Integer]) }
    def rarity_counts(items = self.items)
      items.each_with_object(T.let({}, T::Hash[RarityTier, Integer])) do |item, counts|
        tier = RarityTier.for(market_hash_name: item.market_hash_name, rarity: item.metadata["rarity"])
        next unless tier

        counts[tier] = (counts[tier] || 0) + 1
      end
    end

    private

    sig { returns(T::Array[Item]) }
    def build_items
      pool_by_name = Demo::ItemPool.entries.index_by { |entry| entry.fetch("market_hash_name") }
      real_by_name = Item.where(market_hash_name: Demo::Inventory.market_hash_names).index_by(&:market_hash_name)

      Demo::Inventory.entries.map do |entry|
        pool_entry = pool_by_name[entry.market_hash_name]
        attrs = ItemParser.parse(
          entry.market_hash_name,
          icon_url: pool_entry["icon_url"],
          marketable: true,
          tradable: true,
          rarity: pool_entry["rarity"],
          category: pool_entry["category"]
        )
        series = series_for(
          entry.market_hash_name,
          anchor_price_for(real_by_name[entry.market_hash_name], entry.base_price_cents)
        )

        Item.new(
          market_hash_name: entry.market_hash_name,
          metadata: attrs[:metadata].stringify_keys,
          current_price_cents: series.current_price_cents,
          change_24h_cents: series.change_24h_cents,
          price_updated_at: Time.current,
          price_unavailable: false
        )
      end
    end

    sig { params(real_item: T.nilable(Item), fallback: Integer).returns(Integer) }
    def anchor_price_for(real_item, fallback)
      return fallback if real_item.nil? || real_item.price_unavailable

      real_item.current_price_cents || fallback
    end

    sig { params(market_hash_name: String, anchor: Integer).returns(Demo::PriceSeries) }
    def series_for(market_hash_name, anchor)
      existing = @series[market_hash_name]
      return existing if existing

      @series[market_hash_name] = Demo::PriceSeries.new(
        market_hash_name: market_hash_name,
        current_price_cents: anchor
      )
    end

    sig { params(item: Item).returns(Demo::PriceSeries) }
    def series_for_item(item)
      series_for(item.market_hash_name, T.must(item.current_price_cents))
    end

    sig { params(range: Options::DateRange).returns(T::Array[InventoryValueQuery::ValueHistory::Point]) }
    def portfolio_points(range)
      return [] if items.empty?

      days = window_days(range)
      totals = portfolio_daily.last(days)
      dates = series_for_item(T.must(items.first)).daily.map(&:at).last(days)

      totals.each_with_index.map do |total, index|
        InventoryValueQuery::ValueHistory::Point.new(
          at: T.must(dates[index]),
          total_value_cents: total,
          complete: true,
          priced_items_count: items.size,
          pricable_items_count: items.size
        )
      end
    end

    sig { returns(T::Array[Integer]) }
    def portfolio_daily
      @portfolio_daily ||= T.let(build_portfolio_daily, T.nilable(T::Array[Integer]))
    end

    sig { returns(T::Array[Integer]) }
    def build_portfolio_daily
      return [] if items.empty?

      series_list = items.map { |item| series_for_item(item).daily }

      (0...HISTORY_DAYS).map do |index|
        series_list.sum { |series| T.must(series[index]).price_cents }
      end
    end

    sig { params(range: Options::DateRange).returns(Integer) }
    def window_days(range)
      case range
      when Options::DateRange::Last24Hours then 1
      when Options::DateRange::Last7Days then 7
      when Options::DateRange::Last30Days then 30
      when Options::DateRange::LastYear, Options::DateRange::AllTime then HISTORY_DAYS
      else T.absurd(range)
      end
    end

    sig { params(points: T::Array[InventoryValueQuery::ValueHistory::Point]).returns(InventoryValueQuery::ValueSnapshot) }
    def snapshot_for(points)
      InventoryValueQuery::ValueSnapshot.new(
        total_value_cents: points.last&.total_value_cents || 0,
        items_count: items.size,
        pricable_items_count: items.size,
        priced_items_count: items.size,
        oldest_price_at: points.first&.at
      )
    end

    sig do
      params(points: T::Array[InventoryValueQuery::ValueHistory::Point])
        .returns(InventoryValueQuery::ValueDelta)
    end
    def delta_for(points)
      return empty_delta if points.empty?

      current = T.must(points.last).total_value_cents
      previous = points[-2]&.total_value_cents || current
      cents = current - previous

      InventoryValueQuery::ValueDelta.new(
        cents: cents,
        percent: previous.zero? ? 0.0 : ((cents.to_f / previous * 100).round(2)).to_f,
        basis_at: points[-2]&.at,
        partial: false,
        available: true
      )
    end

    sig { returns(InventoryValueQuery::ValueDelta) }
    def empty_delta
      InventoryValueQuery::ValueDelta.new(
        cents: 0,
        percent: 0.0,
        basis_at: nil,
        partial: false,
        available: false
      )
    end

    sig { params(raw: T.untyped).returns(Options::DateRange) }
    def parse_value_range(raw)
      Options::DateRange::Param.new(
        allowed_ranges: InventoryValueQuery::SUPPORTED_RANGES,
        default: Options::DateRange::Last7Days,
        error_class: Api::Demo::UnsupportedParamError
      ).parse(raw)
    end

    sig { params(raw: T.untyped).returns(Options::DateRange) }
    def parse_history_range(raw)
      Options::DateRange::Param.new(
        allowed_ranges: Options::DateRange.values,
        default: Options::DateRange::Last30Days,
        error_class: Api::Demo::UnsupportedParamError
      ).parse(raw)
    end

    sig { params(raw: T.untyped).returns(T::Array[Item]) }
    def sort_items(raw)
      option = Options::ItemSortOption.try_deserialize(
        raw.presence || Options::ItemSortOption::PriceDesc.serialize
      )
      raise Api::Demo::UnsupportedParamError, "Unsupported sort: #{raw}" unless option

      case option
      when Options::ItemSortOption::ChangeDesc
        items.sort_by { |item| [ -(item.change_24h_cents || 0), item.market_hash_name ] }
      when Options::ItemSortOption::PriceDesc
        items.sort_by { |item| [ -(item.current_price_cents || 0), item.market_hash_name ] }
      when Options::ItemSortOption::PriceAsc
        items.sort_by { |item| [ item.current_price_cents || 0, item.market_hash_name ] }
      when Options::ItemSortOption::NameAsc
        items.sort_by { |item| [ item.metadata["item_name"].to_s.downcase, item.market_hash_name ] }
      else T.absurd(option)
      end
    end

    sig { params(items: T::Array[Item]).returns(T::Hash[String, T::Array[ItemTrendCache::TrendPoint]]) }
    def trends_for(items)
      items.each_with_object(T.let({}, T::Hash[String, T::Array[ItemTrendCache::TrendPoint]])) do |item, trends|
        trends[item.market_hash_name] = series_for_item(item).trend
      end
    end
  end
end
