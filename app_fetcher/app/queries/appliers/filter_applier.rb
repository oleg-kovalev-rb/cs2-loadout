# typed: strict

module Appliers
  class FilterApplier
    extend T::Sig

    class << self
      extend T::Sig

      sig do
        params(
          scope: ActiveRecord::Relation,
          params: ActionController::Parameters,
          enum_class: T.class_of(T::Enum)
        ).returns(ActiveRecord::Relation)
      end
      def call(scope, params, enum_class:)
        enum_class.values.reduce(scope) { |current, field| T.unsafe(field).apply(current, params) }
      end
    end
  end
end
