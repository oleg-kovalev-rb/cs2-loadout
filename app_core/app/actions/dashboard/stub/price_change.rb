# typed: strict

module Dashboard
  module Stub
    # STUB: app_fetcher's change_24h_cents is always nil today (the field is
    # referenced in its serializer but never actually populated on the Item
    # model). Replace this with real PriceLog-backed deltas once app_fetcher
    # exposes them.
    class PriceChange
      extend T::Sig

      sig { params(market_hash_name: String, price_cents: Integer).returns(Integer) }
      def self.call(market_hash_name, price_cents)
        rng = Random.new(market_hash_name.hash)
        pct = rng.rand(-8.0..8.0)
        (price_cents * pct / 100.0).round
      end
    end
  end
end
