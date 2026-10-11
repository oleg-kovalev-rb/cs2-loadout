# typed: strict

module Appliers
  class FilterApplier
    extend T::Sig

    class << self
      extend T::Sig

      sig { params(scope: ActiveRecord::Relation, params: ActionController::Parameters, enum_class: T.untyped).returns(ActiveRecord::Relation) }
      def call(scope, params, enum_class:)
        enum_class.values.reduce(scope) { |current, field| field.apply(current, params) }
      end
    end
  end
end
