# typed: strict

class RarityTier < T::Enum
  extend T::Sig

  enums do
    Gold = new("gold")
    Covert = new("covert")
    Classified = new("classified")
    Restricted = new("restricted")
    MilSpec = new("mil_spec")
    Industrial = new("industrial")
    Consumer = new("consumer")
  end

  GOLD_PREFIX = T.let("★".freeze, String)

  class << self
    extend T::Sig

    sig { params(item: Item).returns(T.nilable(RarityTier)) }
    def for_item(item)
      return Gold if item.market_hash_name.start_with?(GOLD_PREFIX)

      case item.rarity
      when "Consumer Grade" then Consumer
      when "Industrial Grade" then Industrial
      when "Mil-Spec Grade" then MilSpec
      when "Restricted" then Restricted
      when "Classified" then Classified
      when "Covert" then Covert
      when "Extraordinary", "Contraband" then Gold
      else nil
      end
    end
  end
end
