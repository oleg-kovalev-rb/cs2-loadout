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

    sig { returns(T::Boolean) }
    def not_found?
      status == 404
    end

    module DataClassMethods
      extend T::Sig
      extend T::Helpers

      interface!

      sig { abstract.params(hash: T::Hash[String, T.untyped]).returns(T::Struct) }
      def from_hash(hash); end
    end
  end
end
