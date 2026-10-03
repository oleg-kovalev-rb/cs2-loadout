# typed: strict

class Steam::Response::Data::InventoryData < T::Struct
  extend T::Sig
  extend Steam::Response::DataClassMethods

  const :assets, T::Array[T::Hash[String, T.untyped]]
  const :descriptions, T::Array[T::Hash[String, T.untyped]]
  const :more_items, T::Boolean

  sig { override.params(hash: T::Hash[String, T.untyped]).returns(Steam::Response::Data::InventoryData) }
  def self.from_hash(hash)
    Steam::Response::Data::InventoryData.new(
      assets: hash["assets"] || [],
      descriptions: hash["descriptions"] || [],
      more_items: !!hash["more_items"]
    )
  end

  sig { returns(T::Array[String]) }
  def market_hash_names
    descriptions.map { |desc| desc["market_hash_name"] }.compact.uniq
  end
end
