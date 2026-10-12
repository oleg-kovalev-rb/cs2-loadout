# typed: strict

module Api
  module Admin
    class PriceLogsController < ApplicationController
      extend T::Sig

      sig { void }
      def index
        item = Item.find(params[:item_id])

        render json: { price_logs: item.price_logs.map { |price_log| price_log_json(price_log) } }, status: :ok
      end

      sig { void }
      def destroy
        price_log = PriceLog.find_by!(id: params[:id], item_id: params[:item_id])

        price_log.destroy!
        render json: { message: "Deleted" }, status: :ok
      end

      private

      sig { params(price_log: PriceLog).returns(T::Hash[Symbol, T.untyped]) }
      def price_log_json(price_log)
        {
          id: price_log.id,
          lowest_price_cents: price_log.lowest_price_cents,
          median_price_cents: price_log.median_price_cents,
          volume: price_log.volume,
          created_at: price_log.created_at.iso8601
        }
      end
    end
  end
end
