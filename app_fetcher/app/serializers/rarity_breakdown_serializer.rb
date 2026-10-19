# typed: strict

class RarityBreakdownSerializer
  extend T::Sig

  class << self
    extend T::Sig

    sig do
      params(rarity_counts: T::Hash[RarityTier, Integer])
        .returns(T::Array[T::Hash[Symbol, T.untyped]])
    end
    def call(rarity_counts)
      classified_total = rarity_counts.values.sum

      RarityTier.values.map do |tier|
        count = rarity_counts[tier] || 0
        percent = classified_total.zero? ? 0.0 : (count.to_f / classified_total * 100).round(1)

        { tier: tier.serialize, count: count, percent: percent }
      end
    end
  end
end
