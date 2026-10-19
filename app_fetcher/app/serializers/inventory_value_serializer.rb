# typed: strict

class InventoryValueSerializer
  extend T::Sig

  class << self
    extend T::Sig

    sig { params(value: InventoryValueQuery::InventoryValue).returns(T::Hash[Symbol, T.untyped]) }
    def call(value)
      {
        current: current_json(value.snapshot),
        history: value.history.points.map { |point| point_json(point) },
        change: change_json(value.history.delta)
      }
    end

    private

    sig do
      params(snapshot: T.nilable(InventoryValueQuery::ValueSnapshot))
        .returns(T.nilable(T::Hash[Symbol, T.untyped]))
    end
    def current_json(snapshot)
      return nil if snapshot.nil?

      {
        total_value_cents: snapshot.total_value_cents,
        items_count: snapshot.items_count,
        pricable_items_count: snapshot.pricable_items_count,
        priced_items_count: snapshot.priced_items_count,
        complete: snapshot.complete?,
        oldest_price_at: snapshot.oldest_price_at&.iso8601
      }
    end

    sig { params(point: InventoryValueQuery::ValueHistory::Point).returns(T::Hash[Symbol, T.untyped]) }
    def point_json(point)
      {
        at: point.at.iso8601,
        total_value_cents: point.total_value_cents,
        complete: point.complete,
        priced_items_count: point.priced_items_count,
        pricable_items_count: point.pricable_items_count
      }
    end

    sig { params(delta: InventoryValueQuery::ValueDelta).returns(T::Hash[Symbol, T.untyped]) }
    def change_json(delta)
      {
        cents: delta.cents,
        percent: delta.percent,
        basis_at: delta.basis_at&.iso8601,
        partial: delta.partial,
        available: delta.available
      }
    end
  end
end
