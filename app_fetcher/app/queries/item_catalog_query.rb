# typed: strict

class ItemCatalogQuery
  extend T::Sig

  class PriceStats < T::Struct
    const :gaining_count, Integer
    const :losing_count, Integer
  end

  class Page < T::Struct
    const :items, T::Array[Item]
    const :pagination, Appliers::Pagination
    const :total_count, Integer
    const :price_stats, PriceStats
    const :trends, T::Hash[String, T::Array[ItemTrendCache::TrendPoint]]
    const :last_synced_at, T.nilable(String)
  end

  class << self
    extend T::Sig

    sig { params(params: ActionController::Parameters).returns(Page) }
    def call(params)
      sort_option = Appliers::SortApplier.call(
        params[:sort], enum_class: Options::ItemSortOption, default: Options::ItemSortOption::ChangeDesc
      )
      pagination = Appliers::Pagination.new(params[:page], params[:per_page])

      scope = Appliers::FilterApplier.call(Item.marketable, params, enum_class: Options::ItemFilterField)

      total_count, gaining_count, losing_count = scope.pluck(
        Arel.sql("COUNT(*)"),
        Arel.sql("COUNT(*) FILTER (WHERE change_24h_cents > 0)"),
        Arel.sql("COUNT(*) FILTER (WHERE change_24h_cents < 0)")
      ).first

      page_items = sort_option.apply(scope).limit(pagination.per_page).offset(pagination.offset).to_a

      Page.new(
        items: page_items,
        pagination: pagination,
        total_count: total_count,
        price_stats: PriceStats.new(gaining_count: gaining_count, losing_count: losing_count),
        trends: ItemTrendCache.fetch_for(page_items.map(&:market_hash_name)),
        last_synced_at: Item.marketable.maximum(:updated_at)&.iso8601
      )
    end
  end
end
