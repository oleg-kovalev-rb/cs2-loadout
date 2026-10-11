# typed: strict

module Options
  class ItemSortOption < T::Enum
    extend T::Sig

    enums do
      ChangeDesc = new("change_24h_desc")
      PriceDesc = new("price_desc")
      PriceAsc = new("price_asc")
      NameAsc = new("name_asc")
    end

    sig { params(scope: ActiveRecord::Relation).returns(ActiveRecord::Relation) }
    def apply(scope)
      case self
      when ChangeDesc then scope.order(change_24h_cents: :desc)
      when PriceDesc then scope.order(current_price_cents: :desc)
      when PriceAsc then scope.order(current_price_cents: :asc)
      when NameAsc then scope.order(Arel.sql("metadata->>'item_name' ASC"))
      else T.absurd(self)
      end
    end
  end
end
