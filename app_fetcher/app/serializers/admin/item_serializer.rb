# typed: strict

module Admin
  class ItemSerializer
    extend T::Sig

    class << self
      extend T::Sig

      sig { params(meta: T::Hash[Symbol, Integer], items: T::Enumerable[Item]).returns(T::Hash[Symbol, T.untyped]) }
      def call_for_list(meta, items)
        { meta: meta, items: items.map { |item| item_json(item) } }
      end

      sig { params(item: Item).returns(T::Hash[Symbol, T.untyped]) }
      def call(item)
        { item: item_json(item) }
      end

      private

      sig { params(item: Item).returns(T::Hash[Symbol, T.untyped]) }
      def item_json(item)
        {
          id: item.id,
          market_hash_name: item.market_hash_name,
          metadata: {
            weapon_type: item.weapon_type,
            item_name: item.item_name,
            condition: item.condition,
            stattrak: item.stattrak,
            souvenir: item.souvenir,
            icon_url: item.icon_url,
            marketable: item.marketable,
            tradable: item.tradable,
            rarity: item.rarity,
            category: item.category
          },
          current_price_cents: item.current_price_cents,
          change_24h_cents: item.change_24h_cents,
          created_at: item.created_at.iso8601,
          updated_at: item.updated_at.iso8601
        }
      end
    end
  end
end
