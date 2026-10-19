# typed: strict

module Api
  module V1
    class ItemPricesController < BaseController
      extend T::Sig

      sig { void }
      def dynamics
        names = owned_market_hash_names
        priced_items = ItemPriceCache.fetch_for(names)

        PriceWarmupService.call(priced_items.values)
        pending_count = Item.awaiting_price.where(market_hash_name: names).count

        render json: ItemPriceDynamicsSerializer.call(priced_items, pending_count), status: :ok
      end

      sig { void }
      def trend
        render json: ItemTrendCache.fetch_for(owned_market_hash_names), status: :ok
      end

      sig { void }
      def history
        period = PricePeriod.resolve(
          params[:period], supported: PriceLog::SUPPORTED_PERIODS, default: PricePeriod::ThirtyDays
        )

        raise Api::V1::UnsupportedParamError, "Unsupported period: #{params[:period]}" unless period

        item = Item.find_by(market_hash_name: params[:market_hash_name])

        unless item
          render json: [], status: :ok
          return
        end

        points = if period == PricePeriod::ThirtyDays
          PriceHistoryCache.fetch_for([ item.market_hash_name ])[item.market_hash_name] || []
        else
          PriceLog.where(item_id: item.id).for_period(period).order(:created_at).map do |log|
            { at: log.created_at.iso8601, price_cents: log.lowest_price_cents, volume: log.volume }
          end
        end

        render json: points, status: :ok
      end

      private

      sig { returns(T::Array[String]) }
      def owned_market_hash_names
        (UserInventoryCache.fetch(current_steam_id) || []).map(&:market_hash_name)
      end
    end
  end
end
