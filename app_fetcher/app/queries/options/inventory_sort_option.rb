# typed: strict

module Options
  class InventorySortOption < T::Enum
    extend T::Sig

    enums do
      ValueDesc = new("value_desc")
      ValueAsc = new("value_asc")
      ItemsDesc = new("items_desc")
      ItemsAsc = new("items_asc")
    end

    sig { params(scope: ActiveRecord::Relation).returns(ActiveRecord::Relation) }
    def apply(scope)
      case self
      when ValueDesc then scope.order(Arel.sql("total_value_cents DESC"))
      when ValueAsc then scope.order(Arel.sql("total_value_cents ASC"))
      when ItemsDesc then scope.order(Arel.sql("items_count DESC"))
      when ItemsAsc then scope.order(Arel.sql("items_count ASC"))
      else T.absurd(self)
      end
    end
  end
end
