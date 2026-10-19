# typed: strict

module Options
  class ItemFilterOption < T::Enum
    extend T::Sig

    enums do
      Category = new("category")
      Rarity = new("rarity")
      Stattrak = new("stattrak")
      Search = new("search")
    end

    T::Sig::WithoutRuntime.sig do
      params(scope: Item::PrivateRelation, params: ActionController::Parameters).returns(Item::PrivateRelation)
    end
    def apply(scope, params)
      case self
      when Category then scope.by_categories(Array(params[:category]).map(&:to_s))
      when Rarity then scope.by_rarities(Array(params[:rarity]).map(&:to_s))
      when Stattrak then params[:stattrak] == "true" ? scope.stattrak_only : scope
      when Search then scope.matching_search(params[:search].presence&.to_s&.downcase)
      else T.absurd(self)
      end
    end
  end
end
