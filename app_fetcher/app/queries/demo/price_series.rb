# typed: strict

require "digest"

module Demo
  class PriceSeries
    extend T::Sig

    class Point < T::Struct
      const :at, Time
      const :price_cents, Integer
      const :volume, Integer
    end

    DAYS = T.let(365, Integer)
    HOURS = T.let(24, Integer)
    TREND_INDEXES = T.let([ 0, 1, 3, 5, 6 ].freeze, T::Array[Integer])
    DAILY_SWING = T.let(0.035, Float)
    HOURLY_SWING = T.let(0.006, Float)
    MIN_PRICE_CENTS = T.let(1, Integer)
    MIN_MULTIPLIER = T.let(0.5, Float)
    MAX_MULTIPLIER = T.let(2.0, Float)

    sig { returns(Integer) }
    attr_reader :current_price_cents

    sig { params(market_hash_name: String, current_price_cents: Integer).void }
    def initialize(market_hash_name:, current_price_cents:)
      @market_hash_name = market_hash_name
      @current_price_cents = T.let([ current_price_cents, MIN_PRICE_CENTS ].max, Integer)
      @seed = T.let(Digest::SHA256.hexdigest(market_hash_name).first(8).to_i(16), Integer)
      @daily = T.let(nil, T.nilable(T::Array[Point]))
      @hourly = T.let(nil, T.nilable(T::Array[Point]))
    end

    sig { returns(T::Array[Point]) }
    def daily
      @daily ||= T.let(build_daily, T.nilable(T::Array[Point]))
    end

    sig { returns(T::Array[Point]) }
    def hourly
      @hourly ||= T.let(build_hourly, T.nilable(T::Array[Point]))
    end

    sig { params(range: Options::DateRange).returns(T::Array[Point]) }
    def points_for(range)
      case range
      when Options::DateRange::Last24Hours then hourly
      when Options::DateRange::AllTime then daily_window(nil)
      else daily_window(range.since_date)
      end
    end

    sig { returns(Integer) }
    def change_24h_cents
      current_price_cents - T.must(daily[-2]).price_cents
    end

    sig { returns(T::Array[ItemTrendCache::TrendPoint]) }
    def trend
      points = daily.last(7)

      TREND_INDEXES.map do |index|
        point = T.must(points[index])

        { at: point.at.iso8601, price_cents: point.price_cents, volume: point.volume }
      end
    end

    private

    sig { returns(T::Array[Point]) }
    def build_daily
      random = Random.new(@seed)
      today = Date.current
      dates = (0...DAYS).map { |offset| today - (DAYS - 1 - offset) }
      values = T.let([ @current_price_cents ], T::Array[Integer])

      (DAYS - 1).times do
        previous = (T.must(values.last) * (1.0 + ((random.rand - 0.5) * 2.0 * DAILY_SWING))).round
        values << previous.clamp(lower_bound, upper_bound)
      end

      values.reverse.zip(dates).map do |price, date|
        Point.new(
          at: Time.utc(date.year, date.month, date.day),
          price_cents: price,
          volume: volume_for(date.jd)
        )
      end
    end

    sig { returns(T::Array[Point]) }
    def build_hourly
      random = Random.new(@seed + 1)
      now = Time.current.to_time
      start = T.must(daily[-2]).price_cents
      values = T.let([ start ], T::Array[Integer])

      (HOURS - 1).times do |index|
        progress = (index + 1).to_f / HOURS
        target = start + ((@current_price_cents - start) * progress)
        noise = target * ((random.rand - 0.5) * 2.0 * HOURLY_SWING)
        values << [ (target + noise).round, MIN_PRICE_CENTS ].max
      end
      values << @current_price_cents

      values.each_with_index.map do |price, index|
        at = now - (HOURS - index).hours

        Point.new(
          at: at,
          price_cents: price,
          volume: volume_for(at.to_i / 3600)
        )
      end
    end

    # Mirrors InventoryValueQuery.history: every daily point from the range's
    # cutoff through yesterday, plus a live point at "now". Slicing the last
    # N daily points instead would span only N - 1 days and leave the hero
    # chart's left edge empty (see agent/styleguides/fetcher/demo-api.md).
    sig { params(since_date: T.nilable(Date)).returns(T::Array[Point]) }
    def daily_window(since_date)
      today = Date.current
      window = daily.reject { |point| point.at.to_date >= today }
      window = window.select { |point| point.at.to_date >= since_date } if since_date
      window + [ live_point ]
    end

    sig { returns(Point) }
    def live_point
      at = Time.current.utc

      Point.new(at: at, price_cents: @current_price_cents, volume: volume_for(at.to_i / 3600))
    end

    sig { params(salt: Integer).returns(Integer) }
    def volume_for(salt)
      Random.new(@seed + salt).rand(1..500)
    end

    sig { returns(Integer) }
    def lower_bound
      [ (@current_price_cents * MIN_MULTIPLIER).round, MIN_PRICE_CENTS ].max
    end

    sig { returns(Integer) }
    def upper_bound
      [ (@current_price_cents * MAX_MULTIPLIER).round, lower_bound ].max
    end
  end
end
