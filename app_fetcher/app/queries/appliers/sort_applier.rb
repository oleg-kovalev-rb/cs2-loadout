# typed: strict

module Appliers
  class SortApplier
    extend T::Sig

    class << self
      extend T::Sig

      sig do
        params(
          scope: ActiveRecord::Relation,
          params: ActionController::Parameters,
          enum_class: T.class_of(T::Enum),
          default: T::Enum,
          param_name: String
        ).returns(ActiveRecord::Relation)
      end
      def call(scope, params, enum_class:, default:, param_name: "sort")
        raw_value = params[param_name]
        option = enum_class.try_deserialize(raw_value.presence || default.serialize)
        raise Api::Public::UnsupportedParamError, "Unsupported #{param_name}: #{raw_value}" unless option

        T.unsafe(option).apply(scope)
      end
    end
  end
end
