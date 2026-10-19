# typed: strict

class ItemPriceHistorySerializer
  extend T::Sig

  class << self
    extend T::Sig

    sig do
      params(history: ItemPriceHistoryQuery::ItemPriceHistory)
        .returns(T::Array[T::Hash[Symbol, T.untyped]])
    end
    def call(history)
      history.points.map do |point|
        { at: point.at.iso8601, price_cents: point.price_cents, volume: point.volume }
      end
    end
  end
end
