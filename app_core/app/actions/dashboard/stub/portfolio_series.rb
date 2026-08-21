# typed: strict

module Dashboard
  module Stub
    # STUB: no PriceLog history is exposed by app_fetcher yet. Generates a
    # plausible walk ending at the *real* current portfolio total. Replace the
    # walk generation once historical price data has an API — the
    # current_value_cents this produces is already real.
    class PortfolioSeries
      extend T::Sig

      # Data points per range. Keep numerically in sync with the frontend's
      # app/frontend/dashboard/chartConfig.js RANGE_POINTS whenever either is retuned.
      RANGE_POINTS = T.let({ "24h" => 24, "7d" => 7, "30d" => 30 }.freeze, T::Hash[String, Integer])

      sig { params(items: T::Array[T::Hash[Symbol, T.untyped]]).returns(T::Hash[Symbol, T.untyped]) }
      def self.call(items)
        current_total_cents = items.sum { |item| item[:current_price_cents] || 0 }

        series = RANGE_POINTS.transform_values do |points|
          build_series(current_total_cents, points)
        end

        { current_value_cents: current_total_cents, series: series }
      end

      sig { params(end_value_cents: Integer, points: Integer).returns(T::Array[Integer]) }
      def self.build_series(end_value_cents, points)
        rng = Random.new(end_value_cents + points)
        start_value = (end_value_cents * rng.rand(0.92..0.98)).round

        Array.new(points) do |i|
          t = points == 1 ? 1.0 : i / (points - 1).to_f
          base = start_value + (end_value_cents - start_value) * t
          wiggle = (rng.rand - 0.5) * (end_value_cents * 0.01)
          (base + wiggle).round
        end.tap { |values| values[-1] = end_value_cents }
      end
      private_class_method :build_series
    end
  end
end
