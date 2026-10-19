# typed: strict

class ItemMetadataSerializer
  extend T::Sig

  class << self
    extend T::Sig

    sig { params(item: Item).returns(T::Hash[Symbol, T.untyped]) }
    def call(item)
      {
        weapon_type: item.weapon_type,
        item_name: item.item_name,
        category: item.category,
        condition: item.condition,
        stattrak: item.stattrak,
        icon_url: item.icon_url,
        rarity: item.rarity
      }
    end
  end
end
