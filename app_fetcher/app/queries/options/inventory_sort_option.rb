# typed: strict

module Options
  class InventorySortOption < T::Enum
    extend T::Sig

    enums do
      ValueDesc = new("value_desc")
      ItemsDesc = new("items_desc")
      RecentlySynced = new("recently_synced")
      ChangeDesc = new("change_24h_desc")
    end

    sig { params(scope: ActiveRecord::Relation).returns(ActiveRecord::Relation) }
    def apply(scope)
      case self
      when ValueDesc then scope.order(Arel.sql("total_value_cents DESC"))
      when ItemsDesc then scope.order(Arel.sql("items_count DESC"))
      when RecentlySynced then scope.order(user_inventories: { updated_at: :desc })
      when ChangeDesc then scope.order(Arel.sql("change_24h_cents DESC"))
      else T.absurd(self)
      end
    end
  end
end
