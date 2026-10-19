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
        item = Item.find_by!(market_hash_name: params[:market_hash_name])

        points = if params[:period] == ::Options::DateRange::Last30Days.serialize
          PriceHistoryCache.fetch_for([ item.market_hash_name ])[item.market_hash_name] || []
        else
          ItemPriceHistoryQuery.call(item, params).points.map do |point|
            { at: point.at, price_cents: point.price_cents, volume: point.volume }
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
