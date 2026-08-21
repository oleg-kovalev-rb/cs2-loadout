# typed: strict

module Dashboard
  module Stub
    # STUB: no market-volume data source exists anywhere yet (would require
    # Steam Market API integration in app_fetcher). Flat plausible placeholder.
    class MarketVolume
      extend T::Sig

      sig { returns(T::Hash[Symbol, T.untyped]) }
      def self.call
        rng = Random.new(Date.today.jd)
        base = 14_000
        sparkline = Array.new(15) { |i| base + (i * 350) + rng.rand(-800..800) }

        { count_24h: sparkline.last, sparkline: sparkline }
      end
    end
  end
end
