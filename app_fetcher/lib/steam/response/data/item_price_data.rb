# typed: strict

class Steam::Response::Data::ItemPriceData < T::Struct
  extend T::Sig
  extend Steam::Response::DataClassMethods

  const :lowest_price, T.nilable(String)
  const :median_price, T.nilable(String)
  const :volume, T.nilable(String)

  sig { override.params(hash: T::Hash[String, T.untyped]).returns(Steam::Response::Data::ItemPriceData) }
  def self.from_hash(hash)
    Steam::Response::Data::ItemPriceData.new(
      lowest_price: hash["lowest_price"],
      median_price: hash["median_price"],
      volume: hash["volume"]
    )
  end
end
