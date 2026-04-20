# typed: strict

module Steam
  class Response < T::Struct
    extend T::Generic
    extend T::Sig

    DataClass = type_member

    const :status, Integer
    const :data, T.nilable(DataClass)
    const :error, T.nilable(String)

    sig { returns(T::Boolean) }
    def success?
      status == 200
    end

    module DataClassMethods
      extend T::Sig
      extend T::Helpers

      interface!

      sig { abstract.params(hash: T::Hash[String, T.untyped]).returns(T::Struct) }
      def from_hash(hash); end
    end
  end

  SteamDataObjects = T.type_alias do
    T.any(
      ItemPriceData
    )
  end

  class ItemPriceData < T::Struct
    extend T::Sig

    extend Response::DataClassMethods

    const :lowest_price, T.nilable(String)
    const :median_price, T.nilable(String)
    const :volume, T.nilable(String)

    sig { override.params(hash: T::Hash[String, T.untyped]).returns(ItemPriceData) }
    def self.from_hash(hash)
      ItemPriceData.new(
        lowest_price: hash["lowest_price"],
        median_price: hash["median_price"],
        volume: hash["volume"]
      )
    end
  end
end
