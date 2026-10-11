# typed: strict

class InventoryCatalogQuery
  extend T::Sig

  DEFAULT_PER_PAGE = T.let(24, Integer)

  AGGREGATE_COLUMNS = T.let(
    [
      "user_inventories.id",
      "user_inventories.steam_id",
      "user_inventories.updated_at",
      "COUNT(items.id) AS items_count",
      "COALESCE(SUM(items.current_price_cents), 0) AS total_value_cents",
      "COALESCE(SUM(items.change_24h_cents), 0) AS change_24h_cents"
    ].freeze,
    T::Array[String]
  )

  class InventorySummary < T::Struct
    const :steam_id, String
    const :items_count, Integer
    const :total_value_cents, Integer
    const :change_24h_cents, Integer
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
      sort_option = Appliers::SortApplier.call(
        params[:sort], enum_class: Options::InventorySortOption, default: Options::InventorySortOption::ValueDesc
      )
      pagination = Appliers::Pagination.new(params[:page], params[:per_page], default_per_page: DEFAULT_PER_PAGE)

      scope = sort_option.apply(
        UserInventory.left_joins(user_inventory_items: :item).group("user_inventories.id")
      )

      rows = scope.limit(pagination.per_page).offset(pagination.offset).pluck(*AGGREGATE_COLUMNS.map { |column| Arel.sql(column) })
      rarity_counts_by_id = rarity_counts_for(rows.map { |row| row[0] })

      Page.new(
        inventories: rows.map { |row| build_summary(row, rarity_counts_by_id[row[0]] || {}) },
        pagination: pagination,
        total_count: UserInventory.count
      )
    end

    private

    sig { params(row: T::Array[T.untyped], rarity_counts: T::Hash[RarityTier, Integer]).returns(InventorySummary) }
    def build_summary(row, rarity_counts)
      _id, steam_id, updated_at, items_count, total_value_cents, change_24h_cents = row

      InventorySummary.new(
        steam_id: steam_id,
        items_count: items_count,
        total_value_cents: total_value_cents,
        change_24h_cents: change_24h_cents,
        last_synced_at: updated_at.iso8601,
        rarity_counts: rarity_counts
      )
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
