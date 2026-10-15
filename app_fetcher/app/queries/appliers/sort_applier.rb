# typed: strict

module Appliers
  class SortApplier
    extend T::Sig

    class << self
      extend T::Sig

      sig do
        type_parameters(:Enum)
          .params(
            raw_value: T.untyped,
            enum_class: T.class_of(T::Enum),
            default: T.all(T.type_parameter(:Enum), T::Enum),
            param_name: String
          ).returns(T.type_parameter(:Enum))
      end
      def call(raw_value, enum_class:, default:, param_name: "sort")
        option = enum_class.try_deserialize(raw_value.presence || default.serialize)
        raise Api::Public::UnsupportedParamError, "Unsupported #{param_name}: #{raw_value}" unless option

        T.unsafe(option)
      end
    end
  end
end
