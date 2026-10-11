# typed: strict

module Appliers
  class SortApplier
    extend T::Sig

    class << self
      extend T::Sig

      sig { params(raw_value: T.untyped, enum_class: T.untyped, default: T::Enum, param_name: String).returns(T::Enum) }
      def call(raw_value, enum_class:, default:, param_name: "sort")
        option = enum_class.try_deserialize(raw_value.presence || default.serialize)
        raise Api::Public::UnsupportedParamError, "Unsupported #{param_name}: #{raw_value}" unless option

        option
      end
    end
  end
end
