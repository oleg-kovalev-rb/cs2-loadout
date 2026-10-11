# typed: strict

module Api
  module Public
    class ItemsController < ApplicationController
      extend T::Sig

      DEFAULT_PAGE = T.let(1, Integer)
      DEFAULT_PER_PAGE = T.let(24, Integer)
      MIN_PAGE = T.let(1, Integer)
      MIN_PER_PAGE = T.let(1, Integer)
      MAX_PER_PAGE = T.let(100, Integer)
      ALLOWED_SORTS = T.let(
        %w[change_24h_desc price_desc price_asc name_asc].freeze,
        T::Array[String]
      )

      sig { void }
      def catalog
        sort = params[:sort].presence || "change_24h_desc"

        unless ALLOWED_SORTS.include?(sort)
          render json: { message: "Unsupported sort: #{sort}" }, status: :bad_request
          return
        end

        filters = normalized_filters(sort)
        payload = ItemCatalogCache.read(filters)

        if payload.nil?
          payload = compute_page(filters)
          ItemCatalogCache.write(filters, payload)
        end

        if stale?(etag: [ filters, payload[:meta][:last_synced_at] ], public: true)
          render json: payload, status: :ok
        end
      end

      private

      sig { params(sort: String).returns(ItemCatalogCache::NormalizedFilters) }
      def normalized_filters(sort)
        {
          page: clamp_param(params[:page], default: DEFAULT_PAGE, min: MIN_PAGE),
          per_page: clamp_param(params[:per_page], default: DEFAULT_PER_PAGE, min: MIN_PER_PAGE, max: MAX_PER_PAGE),
          search: params[:search].presence&.to_s&.downcase,
          category: Array(params[:category]).map(&:to_s).sort,
          rarity: Array(params[:rarity]).map(&:to_s).sort,
          stattrak: params[:stattrak] == "true",
          sort: sort
        }
      end

      sig { params(raw: T.untyped, default: Integer, min: Integer, max: T.nilable(Integer)).returns(Integer) }
      def clamp_param(raw, default:, min:, max: nil)
        return default if raw.blank?

        value = [ raw.to_s.to_i, min ].max
        max ? [ value, max ].min : value
      end

      sig { params(filters: ItemCatalogCache::NormalizedFilters).returns(T::Hash[Symbol, T.untyped]) }
      def compute_page(filters)
        scope = Item.marketable
                    .by_categories(filters[:category])
                    .by_rarities(filters[:rarity])
                    .matching_search(filters[:search])
        scope = scope.stattrak_only if filters[:stattrak]

        total_count, gaining_count, losing_count = scope.pluck(
          Arel.sql("COUNT(*)"),
          Arel.sql("COUNT(*) FILTER (WHERE change_24h_cents > 0)"),
          Arel.sql("COUNT(*) FILTER (WHERE change_24h_cents < 0)")
        ).first

        offset = (filters[:page] - 1) * filters[:per_page]
        page_items = scope.sorted_by(filters[:sort]).limit(filters[:per_page]).offset(offset).to_a
        trends = ItemTrendCache.fetch_for(page_items.map(&:market_hash_name))

        {
          meta: {
            page: filters[:page],
            per_page: filters[:per_page],
            total_count: total_count,
            total_pages: total_count.zero? ? 0 : (total_count.to_f / filters[:per_page]).ceil,
            gaining_count: gaining_count,
            losing_count: losing_count,
            last_synced_at: Item.marketable.maximum(:updated_at)&.iso8601
          },
          items: page_items.map { |item| item_json(item, trends) }
        }
      end

      sig do
        params(
          item: Item,
          trends: T::Hash[String, T::Array[ItemTrendCache::TrendPoint]]
        ).returns(T::Hash[Symbol, T.untyped])
      end
      def item_json(item, trends)
        change = item.change_24h_cents || 0
        current = item.current_price_cents
        base = current.nil? ? nil : current - change
        percent = (base.nil? || base.zero?) ? 0.0 : (change.to_f / base * 100).round(2)

        {
          market_hash_name: item.market_hash_name,
          metadata: {
            weapon_type: item.weapon_type,
            item_name: item.item_name,
            category: item.category,
            condition: item.condition,
            stattrak: item.stattrak,
            icon_url: item.icon_url,
            rarity: item.rarity
          },
          current_price_cents: current,
          change_24h_cents: change,
          change_24h_percent: percent,
          trend_7d: (trends[item.market_hash_name] || []).map { |point| { at: point[:at], price_cents: point[:price_cents] } }
        }
      end
    end
  end
end
