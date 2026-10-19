# typed: strict

class InventorySerializer
  extend T::Sig

  class << self
    extend T::Sig

    sig { params(items: T::Array[Item]).returns(T::Hash[Symbol, T.untyped]) }
    def call(items)
      {
        items_count: items.size,
        items: items.map { |item| item_json(item) }
      }
    end

    private

    sig { params(item: Item).returns(T::Hash[Symbol, T.untyped]) }
    def item_json(item)
      {
        market_hash_name: item.market_hash_name,
        price_unavailable: item.price_unavailable,
        metadata: item.metadata
      }
    end
  end
end
