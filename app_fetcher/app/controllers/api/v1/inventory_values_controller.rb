# typed: strict

module Api
  module V1
    class InventoryValuesController < ApplicationController
      extend T::Sig

      ALLOWED_PERIODS = T.let(
        [ PricePeriod::SevenDays, PricePeriod::ThirtyDays, PricePeriod::OneYear, PricePeriod::All ].freeze,
        T::Array[PricePeriod]
      )

      sig { void }
      def index
        period = PricePeriod.try_deserialize(params[:period].presence || "all")

        unless period && ALLOWED_PERIODS.include?(period)
          render json: { message: "Unsupported period: #{params[:period]}" }, status: :bad_request
          return
        end

        seed_if_empty
        page = InventoryValuation.page(current_steam_id, period)

        render json: payload(page), status: :ok
      end

      private

      sig { void }
      def seed_if_empty
        return unless InventoryValueLog.where(steam_id: current_steam_id).empty?

        InventoryValueRecordingService.call(current_steam_id)
      end

      sig { params(page: InventoryValuation::Page).returns(T::Hash[Symbol, T.untyped]) }
      def payload(page)
        {
          current: current_json(page.current),
          history: page.series.points.map { |point| point_json(point) },
          change: {
            cents: page.series.change_cents,
            percent: page.series.change_percent,
            basis_at: page.series.change_basis_at,
            partial: page.series.change_partial,
            available: page.series.change_available
          }
        }
      end

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
    end
  end
end
