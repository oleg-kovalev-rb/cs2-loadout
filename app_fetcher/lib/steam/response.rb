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
      Response::Data::ItemPriceData,
      Response::Data::InventoryData
    )
  end
end
