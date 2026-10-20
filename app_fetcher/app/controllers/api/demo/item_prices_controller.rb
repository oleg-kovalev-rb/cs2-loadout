# typed: strict

module Api
  module Demo
    class ItemPricesController < BaseController
      extend T::Sig

      sig { void }
      def dynamics
        priced_items = ItemPriceCache.fetch_for(demo_dataset.items.map(&:market_hash_name))

        render json: ItemPriceDynamicsSerializer.call(priced_items, 0), status: :ok
      end

      sig { void }
      def trend
        render json: ItemTrendCache.fetch_for(demo_dataset.items.map(&:market_hash_name)), status: :ok
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
    end
  end
end
