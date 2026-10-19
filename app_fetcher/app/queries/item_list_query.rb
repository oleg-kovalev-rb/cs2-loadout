# typed: strict

class ItemListQuery
  extend T::Sig

  DEFAULT_PER_PAGE = T.let(25, Integer)

  class PriceChangeStats < T::Struct
    const :gaining_count, Integer
    const :losing_count, Integer
  end

  class ItemCatalog < T::Struct
    const :items, T::Array[Item]
    const :pagination, Appliers::Pagination
    const :total_count, Integer
    const :price_change_stats, PriceChangeStats
    const :trends, T::Hash[String, T::Array[ItemTrendCache::TrendPoint]]
    const :last_synced_at, T.nilable(Time)
  end

  class << self
    extend T::Sig

    sig { params(params: ActionController::Parameters).returns(ItemCatalog) }
    def call(params)
      pagination = Appliers::Pagination.new(params[:page], params[:per_page], default_per_page: DEFAULT_PER_PAGE)

      scope = Appliers::FilterApplier.call(Item.marketable, params, enum_class: Options::ItemFilterOption)

      total_count, gaining_count, losing_count = scope.pluck(
        Arel.sql("COUNT(*)"),
        Arel.sql("COUNT(*) FILTER (WHERE change_24h_cents > 0)"),
        Arel.sql("COUNT(*) FILTER (WHERE change_24h_cents < 0)")
      ).first

      scope = Appliers::SortApplier.call(
        scope, params, enum_class: Options::ItemSortOption, default: Options::ItemSortOption::ChangeDesc
      )

      page_items = pagination.apply(scope).to_a

      ItemCatalog.new(
        items: page_items,
        pagination: pagination,
        total_count: total_count,
        price_change_stats: PriceChangeStats.new(gaining_count: gaining_count, losing_count: losing_count),
        trends: ItemTrendCache.fetch_for(page_items.map(&:market_hash_name)),
        last_synced_at: Item.marketable.maximum(:updated_at)&.to_time&.utc
      )
    end
  end
end
