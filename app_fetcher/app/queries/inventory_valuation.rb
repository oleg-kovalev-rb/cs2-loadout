# typed: strict

# Shared, read-only valuation calculation. It owns the single definition of
# "what this inventory is worth now" (latest known price per item) and the
# daily history/change series derived from InventoryValueLog. Callers are the
# recording service, the public catalog/detail queries, and the V1 values
# endpoint; it performs no writes and shapes no response hashes.
class InventoryValuation
  extend T::Sig

  PRICABLE_SQL = T.let(
    %q(items.metadata @> '{"marketable": true}'::jsonb AND items.price_unavailable = FALSE),
    String
  )

  TOTAL_EXPRESSION = T.let("COALESCE(SUM(items.current_price_cents), 0)", String)
  ITEMS_COUNT_EXPRESSION = T.let("COUNT(items.id)", String)
  PRICABLE_COUNT_EXPRESSION = T.let("COUNT(items.id) FILTER (WHERE #{PRICABLE_SQL})", String)
  PRICED_COUNT_EXPRESSION = T.let(
    "COUNT(items.id) FILTER (WHERE (#{PRICABLE_SQL}) AND items.current_price_cents IS NOT NULL)",
    String
  )
  OLDEST_PRICE_EXPRESSION = T.let(
    "MIN(items.price_updated_at) FILTER (WHERE (#{PRICABLE_SQL}) AND items.current_price_cents IS NOT NULL)",
    String
  )

  AGGREGATE_EXPRESSIONS = T.let(
    [
      TOTAL_EXPRESSION,
      ITEMS_COUNT_EXPRESSION,
      PRICABLE_COUNT_EXPRESSION,
      PRICED_COUNT_EXPRESSION,
      OLDEST_PRICE_EXPRESSION
    ].freeze,
    T::Array[String]
  )

  AGGREGATE_COLUMNS = T.let(
    [
      "#{TOTAL_EXPRESSION} AS total_value_cents",
      "#{ITEMS_COUNT_EXPRESSION} AS items_count",
      "#{PRICABLE_COUNT_EXPRESSION} AS pricable_items_count",
      "#{PRICED_COUNT_EXPRESSION} AS priced_items_count",
      "#{OLDEST_PRICE_EXPRESSION} AS oldest_price_at"
    ].freeze,
    T::Array[String]
  )

  class Snapshot < T::Struct
    extend T::Sig

    const :total_value_cents, Integer
    const :items_count, Integer
    const :pricable_items_count, Integer
    const :priced_items_count, Integer
    const :oldest_price_at, T.nilable(Time)

    sig { returns(T::Boolean) }
    def complete?
      priced_items_count >= pricable_items_count
    end
  end

  class Point < T::Struct
    const :at, String
    const :total_value_cents, Integer
    const :complete, T::Boolean
    const :priced_items_count, T.nilable(Integer)
    const :pricable_items_count, T.nilable(Integer)
  end

  class Series < T::Struct
    const :points, T::Array[Point]
    const :change_cents, Integer
    const :change_percent, Float
    const :change_basis_at, T.nilable(String)
    const :change_partial, T::Boolean
    const :change_available, T::Boolean
  end

  class Page < T::Struct
    const :current, T.nilable(Snapshot)
    const :series, Series
  end

  class << self
    extend T::Sig

    sig { params(user_inventory: UserInventory).returns(Snapshot) }
    def current(user_inventory)
      row = user_inventory.items.pick(
        Arel.sql(TOTAL_EXPRESSION),
        Arel.sql(ITEMS_COUNT_EXPRESSION),
        Arel.sql(PRICABLE_COUNT_EXPRESSION),
        Arel.sql(PRICED_COUNT_EXPRESSION),
        Arel.sql(OLDEST_PRICE_EXPRESSION)
      )
      snapshot_from_row(T.unsafe(row) || [ 0, 0, 0, 0, nil ])
    end

    sig { params(steam_id: String, period: PricePeriod, current: Snapshot).returns(Series) }
    def series(steam_id, period, current:)
      since = period.duration&.ago&.to_date
      logs = InventoryValueLog.where(steam_id: steam_id).order(:log_date).to_a
      logs = logs.select { |log| log.log_date >= since } if since

      points = logs.reject { |log| log.log_date == Date.current }.map { |log| point_from_log(log) }
      points << live_point(current)

      series_from_points(points)
    end

    sig { params(steam_id: String, period: PricePeriod).returns(Page) }
    def page(steam_id, period)
      user_inventory = UserInventory.find_by(steam_id: steam_id)
      return Page.new(current: nil, series: empty_series(T.let([], T::Array[Point]))) if user_inventory.nil?

      snapshot = current(user_inventory)
      Page.new(current: snapshot, series: series(steam_id, period, current: snapshot))
    end

    sig { params(steam_ids: T::Array[String], since_date: Date).returns(T::Hash[String, InventoryValueLog]) }
    def baseline_for(steam_ids, since_date)
      return {} if steam_ids.empty?

      InventoryValueLog
        .where(steam_id: steam_ids, log_date: ..since_date)
        .order(:steam_id, log_date: :desc)
        .select("DISTINCT ON (steam_id) inventory_value_logs.*")
        .index_by(&:steam_id)
    end

    sig { params(row: T::Array[T.untyped]).returns(Snapshot) }
    def snapshot_from_row(row)
      total, items, pricable, priced, oldest = row

      Snapshot.new(
        total_value_cents: total.to_i,
        items_count: items.to_i,
        pricable_items_count: pricable.to_i,
        priced_items_count: priced.to_i,
        oldest_price_at: oldest.respond_to?(:to_time) ? oldest.to_time.utc : nil
      )
    end

    private

    sig { params(log: InventoryValueLog).returns(Point) }
    def point_from_log(log)
      Point.new(
        at: Time.utc(log.log_date.year, log.log_date.month, log.log_date.day).iso8601,
        total_value_cents: log.total_value_cents,
        complete: log.complete?,
        priced_items_count: log.priced_items_count,
        pricable_items_count: log.pricable_items_count
      )
    end

    sig { params(current: Snapshot).returns(Point) }
    def live_point(current)
      Point.new(
        at: Time.current.iso8601,
        total_value_cents: current.total_value_cents,
        complete: current.complete?,
        priced_items_count: current.priced_items_count,
        pricable_items_count: current.pricable_items_count
      )
    end

    sig { params(points: T::Array[Point]).returns(Series) }
    def series_from_points(points)
      return empty_series(points) if points.size < 2

      base = T.must(points.first)
      last = T.must(points.last)
      change = last.total_value_cents - base.total_value_cents
      percent = base.total_value_cents.zero? ? 0.0 : (change.to_f / base.total_value_cents * 100).round(2).to_f

      Series.new(
        points: points,
        change_cents: change,
        change_percent: percent,
        change_basis_at: base.at,
        change_partial: !base.complete || !last.complete,
        change_available: true
      )
    end

    sig { params(points: T::Array[Point]).returns(Series) }
    def empty_series(points)
      Series.new(
        points: points,
        change_cents: 0,
        change_percent: 0.0,
        change_basis_at: nil,
        change_partial: false,
        change_available: false
      )
    end
  end
end
