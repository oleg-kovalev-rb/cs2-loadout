# typed: strict

class InventoryValuationSerializer
  extend T::Sig

  class << self
    extend T::Sig

    sig { params(page: InventoryValuation::Page).returns(T::Hash[Symbol, T.untyped]) }
    def call(page)
      {
        current: current_json(page.current),
        history: page.series.points.map { |point| point_json(point) },
        change: change_json(page.series)
      }
    end

    private

    sig { params(current: T.nilable(InventoryValuation::Snapshot)).returns(T.nilable(T::Hash[Symbol, T.untyped])) }
    def current_json(current)
      return nil if current.nil?

      {
        total_value_cents: current.total_value_cents,
        items_count: current.items_count,
        pricable_items_count: current.pricable_items_count,
        priced_items_count: current.priced_items_count,
        complete: current.complete?,
        oldest_price_at: current.oldest_price_at&.iso8601
      }
    end

    sig { params(point: InventoryValuation::Point).returns(T::Hash[Symbol, T.untyped]) }
    def point_json(point)
      {
        at: point.at,
        total_value_cents: point.total_value_cents,
        complete: point.complete,
        priced_items_count: point.priced_items_count,
        pricable_items_count: point.pricable_items_count
      }
    end

    sig { params(series: InventoryValuation::Series).returns(T::Hash[Symbol, T.untyped]) }
    def change_json(series)
      {
        cents: series.change_cents,
        percent: series.change_percent,
        basis_at: series.change_basis_at,
        partial: series.change_partial,
        available: series.change_available
      }
    end
  end
end
