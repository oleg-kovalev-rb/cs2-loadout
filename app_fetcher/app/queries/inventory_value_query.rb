# typed: strict

class InventoryValueQuery
  extend T::Sig

  BASELINE_MAX_AGE_DAYS = T.let(2, Integer)

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
  AGGREGATE_SELECTS = T.let(
    [
      "#{TOTAL_EXPRESSION} AS total_value_cents",
      "#{ITEMS_COUNT_EXPRESSION} AS items_count",
      "#{PRICABLE_COUNT_EXPRESSION} AS pricable_items_count",
      "#{PRICED_COUNT_EXPRESSION} AS priced_items_count",
      "#{OLDEST_PRICE_EXPRESSION} AS oldest_price_at"
    ].freeze,
    T::Array[String]
  )
  private_constant :AGGREGATE_EXPRESSIONS, :AGGREGATE_SELECTS

  SUPPORTED_RANGES = T.let(
    [
      Options::DateRange::Last7Days,
      Options::DateRange::Last30Days,
      Options::DateRange::LastYear,
      Options::DateRange::AllTime
    ].freeze,
    T::Array[Options::DateRange]
  )

  class ValueSnapshot < T::Struct
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

  class ValueDelta < T::Struct
    const :cents, Integer
    const :percent, Float
    const :basis_at, T.nilable(Time)
    const :partial, T::Boolean
    const :available, T::Boolean
  end

  class ValueHistory < T::Struct
    class Point < T::Struct
      const :at, Time
      const :total_value_cents, Integer
      const :complete, T::Boolean
      const :priced_items_count, T.nilable(Integer)
      const :pricable_items_count, T.nilable(Integer)
    end

    const :points, T::Array[Point]
    const :delta, ValueDelta
  end

  class InventoryValue < T::Struct
    const :snapshot, T.nilable(ValueSnapshot)
    const :history, ValueHistory
  end

  class << self
    extend T::Sig

    sig { params(scope: ActiveRecord::Relation).returns(ActiveRecord::Relation) }
    def with_aggregates(scope)
      scope.select(*T.unsafe(AGGREGATE_SELECTS))
    end

    sig { params(record: UserInventory).returns(ValueSnapshot) }
    def snapshot_from(record)
      ValueSnapshot.new(
        total_value_cents: record.read_attribute(:total_value_cents).to_i,
        items_count: record.read_attribute(:items_count).to_i,
        pricable_items_count: record.read_attribute(:pricable_items_count).to_i,
        priced_items_count: record.read_attribute(:priced_items_count).to_i,
        oldest_price_at: normalize_time(record.read_attribute(:oldest_price_at))
      )
    end

    sig { params(user_inventory: UserInventory).returns(ValueSnapshot) }
    def snapshot_for(user_inventory)
      expressions = AGGREGATE_EXPRESSIONS.map { |expression| Arel.sql(expression) }
      row = user_inventory.items.pick(*T.unsafe(expressions))
      snapshot_from_row(T.unsafe(row) || [ 0, 0, 0, 0, nil ])
    end

    sig do
      params(snapshot: ValueSnapshot, baseline: T.nilable(InventoryValueLog))
        .returns(ValueDelta)
    end
    def delta_for(snapshot, baseline)
      return empty_delta(partial: !snapshot.complete?) if baseline.nil?

      partial = !snapshot.complete? || !baseline.complete?
      basis_at = Time.utc(baseline.log_date.year, baseline.log_date.month, baseline.log_date.day)

      unless baseline.log_date >= Date.current - BASELINE_MAX_AGE_DAYS
        return ValueDelta.new(cents: 0, percent: 0.0, basis_at: basis_at, partial: partial, available: false)
      end

      cents = snapshot.total_value_cents - baseline.total_value_cents

      ValueDelta.new(
        cents: cents,
        percent: percentage(cents, baseline.total_value_cents),
        basis_at: basis_at,
        partial: partial,
        available: true
      )
    end

    sig do
      params(steam_id: String, range: Options::DateRange, current: ValueSnapshot)
        .returns(ValueHistory)
    end
    def history(steam_id, range, current:)
      scope = InventoryValueLog.where(steam_id: steam_id)
      cutoff = range.since_date
      scope = scope.where(log_date: cutoff..) if cutoff

      logs = scope.order(:log_date).to_a
      points = logs.reject { |log| log.log_date == Date.current }.map { |log| point_from_log(log) }
      points << live_point(current)

      history_from_points(points)
    end

    sig { params(steam_id: String, range: Options::DateRange).returns(InventoryValue) }
    def call(steam_id, range)
      user_inventory = UserInventory.find_by(steam_id: steam_id)
      return InventoryValue.new(snapshot: nil, history: empty_history) if user_inventory.nil?

      snapshot = snapshot_for(user_inventory)
      InventoryValue.new(snapshot: snapshot, history: history(steam_id, range, current: snapshot))
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

    private

    sig { params(row: T::Array[T.untyped]).returns(ValueSnapshot) }
    def snapshot_from_row(row)
      total, items, pricable, priced, oldest = row

      ValueSnapshot.new(
        total_value_cents: total.to_i,
        items_count: items.to_i,
        pricable_items_count: pricable.to_i,
        priced_items_count: priced.to_i,
        oldest_price_at: normalize_time(oldest)
      )
    end

    sig { params(value: T.untyped).returns(T.nilable(Time)) }
    def normalize_time(value)
      return nil unless value.respond_to?(:to_time)

      T.unsafe(value).to_time.utc
    end

    sig { params(partial: T::Boolean).returns(ValueDelta) }
    def empty_delta(partial:)
      ValueDelta.new(cents: 0, percent: 0.0, basis_at: nil, partial: partial, available: false)
    end

    sig { params(cents: Integer, base_cents: Integer).returns(Float) }
    def percentage(cents, base_cents)
      return 0.0 if base_cents.zero?

      (cents.to_f / base_cents * 100).round(2).to_f
    end

    sig { params(log: InventoryValueLog).returns(ValueHistory::Point) }
    def point_from_log(log)
      ValueHistory::Point.new(
        at: Time.utc(log.log_date.year, log.log_date.month, log.log_date.day),
        total_value_cents: log.total_value_cents,
        complete: log.complete?,
        priced_items_count: log.priced_items_count,
        pricable_items_count: log.pricable_items_count
      )
    end

    sig { params(current: ValueSnapshot).returns(ValueHistory::Point) }
    def live_point(current)
      ValueHistory::Point.new(
        at: Time.current.utc,
        total_value_cents: current.total_value_cents,
        complete: current.complete?,
        priced_items_count: current.priced_items_count,
        pricable_items_count: current.pricable_items_count
      )
    end

    sig { params(points: T::Array[ValueHistory::Point]).returns(ValueHistory) }
    def history_from_points(points)
      return empty_history(points) if points.size < 2

      base = T.must(points.first)
      last = T.must(points.last)
      cents = last.total_value_cents - base.total_value_cents

      ValueHistory.new(
        points: points,
        delta: ValueDelta.new(
          cents: cents,
          percent: percentage(cents, base.total_value_cents),
          basis_at: base.at,
          partial: !base.complete || !last.complete,
          available: true
        )
      )
    end

    sig { params(points: T::Array[ValueHistory::Point]).returns(ValueHistory) }
    def empty_history(points = T.let([], T::Array[ValueHistory::Point]))
      ValueHistory.new(points: points, delta: empty_delta(partial: false))
    end
  end
end
