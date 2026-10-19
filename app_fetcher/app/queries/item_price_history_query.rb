# typed: strict

class ItemPriceHistoryQuery
  extend T::Sig

  class Point < T::Struct
    const :at, String
    const :price_cents, Integer
    const :volume, Integer
  end

  class Page < T::Struct
    const :range, Options::DateRange
    const :points, T::Array[Point]
  end

  class << self
    extend T::Sig

    sig do
      params(item: Item, params: ActionController::Parameters).returns(Page)
    end
    def call(item, params)
      range = Options::DateRange::Param.new(
        allowed_ranges: Options::DateRange.values,
        default: Options::DateRange::Last30Days,
        error_class: Api::V1::UnsupportedParamError
      ).parse(params[:period])

      scope = PriceLog.where(item_id: item.id)
      cutoff = range.since
      scope = scope.where(created_at: cutoff..) if cutoff

      points = scope.order(:created_at).map do |log|
        Point.new(
          at: log.created_at.iso8601,
          price_cents: log.lowest_price_cents,
          volume: log.volume
        )
      end

      Page.new(range: range, points: points)
    end
  end
end
