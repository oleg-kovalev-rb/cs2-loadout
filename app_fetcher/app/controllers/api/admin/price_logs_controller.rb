# typed: strict

module Api
  module Admin
    class PriceLogsController < BaseController
      extend T::Sig

      sig { void }
      def index
        pagination = Appliers::Pagination.new(params[:page], params[:per_page])
        total_count = PriceLog.count
        price_logs = pagination.apply(PriceLog.includes(:item).order(created_at: :desc))

        render json: ::Admin::PriceLogSerializer.call_for_list(pagination_meta(pagination, total_count), price_logs), status: :ok
      end

      sig { void }
      def destroy
        price_log = PriceLog.find_by!(id: params[:id], item_id: params[:item_id])

        price_log.destroy!
        render json: { message: "Deleted" }, status: :ok
      end
    end
  end
end
