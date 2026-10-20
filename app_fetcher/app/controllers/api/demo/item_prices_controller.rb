# typed: strict

module Api
  module Demo
    class ItemPricesController < BaseController
      extend T::Sig

      sig { void }
      def dynamics
        render json: ItemPriceDynamicsSerializer.call(demo_dataset.priced_items, 0), status: :ok
      end

      sig { void }
      def trend
        render json: demo_dataset.trends, status: :ok
      end

      sig { void }
      def history
        item = demo_dataset.item!(params[:market_hash_name].to_s)
        history = demo_dataset.history(item, period: params[:period])

        render json: ItemPriceHistorySerializer.call(history), status: :ok
      end
    end
  end
end
