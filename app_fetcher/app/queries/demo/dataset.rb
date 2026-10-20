# typed: strict

module Demo
  class Dataset
    extend T::Sig

    ITEM_COUNT = T.let(20, Integer)
    MAX_HISTORY_DAYS = T.let(365, Integer)

    sig { params(seed: Integer).void }
    def initialize(seed:)
      @seed = seed
    end

    sig { returns(T::Array[Item]) }
    def items
      @items ||= T.let(select_items, T.nilable(T::Array[Item]))
    end

    sig { returns(InventoryListQuery::InventorySummary) }
    def summary
      value = self.value

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
      value_for(items, parse_range(period))
    end

    sig { params(params: ActionController::Parameters).returns(InventoryDetailQuery::InventoryDetails) }
    def details(params)
      range = parse_range(params[:period])
      pagination = Appliers::Pagination.new(
        params[:page],
        params[:per_page],
        default_per_page: InventoryDetailQuery::DEFAULT_TOP_ITEMS_PER_PAGE
      )

      sorted = Appliers::SortApplier.call(
        Item.where(id: items.map(&:id)),
        params,
        enum_class: Options::ItemSortOption,
        default: Options::ItemSortOption::PriceDesc,
        param_name: "sort",
        error_class: Api::Demo::UnsupportedParamError
      )
      entries = pagination.apply(sorted).to_a
      value = value_for(items, range)

      InventoryDetailQuery::InventoryDetails.new(
        steam_id: "demo",
        last_synced_at: Time.current.to_time,
        range: range,
        value: value,
        items: InventoryDetailQuery::InventoryItems.new(
          entries: entries,
          pagination: pagination,
          total_count: items.size,
          trends: ItemTrendCache.fetch_for(entries.map(&:market_hash_name))
        ),
        avg_item_value_cents: items.empty? ? 0 : T.must(value.snapshot).total_value_cents / items.size,
        priciest_item: items.max_by { |item| item.current_price_cents || 0 },
        rarity_counts: rarity_counts
      )
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
    def select_items
      random = Random.new(@seed)
      chosen = Demo::ItemPool.market_hash_names.shuffle(random: random).first(ITEM_COUNT)

      by_name = Item
        .where(market_hash_name: chosen)
        .where(price_unavailable: false)
        .where.not(current_price_cents: nil)
        .index_by(&:market_hash_name)

      selected = chosen.filter_map { |name| by_name[name] }
      return selected if selected.size >= ITEM_COUNT

      already_selected = selected.map(&:market_hash_name)
      fallback = Item
        .marketable
        .where(price_unavailable: false)
        .where.not(current_price_cents: nil)
        .where.not(market_hash_name: already_selected)
        .order(:id)
        .limit(ITEM_COUNT - selected.size)
        .to_a

      selected + fallback
    end

    sig { params(raw: T.untyped).returns(Options::DateRange) }
    def parse_range(raw)
      Options::DateRange::Param.new(
        allowed_ranges: InventoryValueQuery::SUPPORTED_RANGES,
        default: Options::DateRange::Last7Days,
        error_class: Api::Demo::UnsupportedParamError
      ).parse(raw)
    end

    sig do
      params(items: T::Array[Item], range: Options::DateRange)
        .returns(InventoryValueQuery::InventoryValue)
    end
    def value_for(items, range)
      snapshot = snapshot_for(items)
      points = history_points(items, range)

      InventoryValueQuery::InventoryValue.new(
        snapshot: snapshot,
        history: InventoryValueQuery::ValueHistory.new(
          points: points,
          delta: delta_for(points)
        )
      )
    end

    sig { params(items: T::Array[Item]).returns(InventoryValueQuery::ValueSnapshot) }
    def snapshot_for(items)
      priced_items = items.select { |item| item.current_price_cents.present? }
      pricable_items = items.select { |item| item.metadata["marketable"] && !item.price_unavailable }

      InventoryValueQuery::ValueSnapshot.new(
        total_value_cents: items.sum { |item| item.current_price_cents.to_i },
        items_count: items.size,
        pricable_items_count: pricable_items.size,
        priced_items_count: priced_items.size,
        oldest_price_at: items.filter_map { |item| item.price_updated_at&.to_time }.min
      )
    end

    sig do
      params(items: T::Array[Item], range: Options::DateRange)
        .returns(T::Array[InventoryValueQuery::ValueHistory::Point])
    end
    def history_points(items, range)
      start_date = range.since_date || (Date.current - MAX_HISTORY_DAYS)
      days = (Date.current - start_date).to_i + 1
      random = Random.new(@seed)
      values = [ items.sum { |item| item.current_price_cents.to_i } ]

      (days - 1).times do
        previous = (values.last * (1 + ((random.rand - 0.5) * 0.08))).round
        values << [ previous, 0 ].max
      end

      values.reverse.each_with_index.map do |total, index|
        date = start_date + index

        InventoryValueQuery::ValueHistory::Point.new(
          at: Time.utc(date.year, date.month, date.day, 12),
          total_value_cents: total,
          complete: true,
          priced_items_count: items.size,
          pricable_items_count: items.size
        )
      end
    end

    sig do
      params(points: T::Array[InventoryValueQuery::ValueHistory::Point])
        .returns(InventoryValueQuery::ValueDelta)
    end
    def delta_for(points)
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
  end
end
