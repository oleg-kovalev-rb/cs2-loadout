# typed: strict

module Api
  module V1
    class ItemPricesController < BaseController
      extend T::Sig

      sig { void }
      def dynamics
        priced_items = ItemPriceCache.fetch_for(market_hash_names)

        PriceWarmupService.call(priced_items.values)
        pending_count = Item.awaiting_price.where(market_hash_name: market_hash_names).count

        render json: ItemPriceDynamicsSerializer.call(priced_items, pending_count), status: :ok
      end

      sig { void }
      def trend
        render json: ItemTrendCache.fetch_for(market_hash_names), status: :ok
      end

      sig { void }
      def history
        item = Item.find_by!(market_hash_name: params[:market_hash_name])
        period = params[:period].presence || ::Options::DateRange::Last30Days.serialize

        points = if period == ::Options::DateRange::Last30Days.serialize
          PriceHistoryCache.fetch_for([ item.market_hash_name ])[item.market_hash_name]
        else
          ItemPriceHistorySerializer.call(ItemPriceHistoryQuery.call(item, params))
        end

        render json: points, status: :ok
      end

      private

      sig { returns(T::Array[String]) }
      def market_hash_names
        @owned_market_hash_names ||= T.let(
          (UserInventoryCache.fetch(current_steam_id) || []).map(&:market_hash_name),
          T.nilable(T::Array[String])
        )
      end
    end
  end
end
