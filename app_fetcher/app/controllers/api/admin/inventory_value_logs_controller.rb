# typed: strict

module Api
  module Admin
    class InventoryValueLogsController < BaseController
      extend T::Sig

      sig { void }
      def index
        pagination = Appliers::Pagination.new(params[:page], params[:per_page])
        total_count = InventoryValueLog.count
        logs = pagination.apply(InventoryValueLog.order(log_date: :desc))

        render json: ::Admin::InventoryValueLogSerializer.call_for_list(pagination_meta(pagination, total_count), logs), status: :ok
      end

      sig { void }
      def destroy
        log = InventoryValueLog.find_by!(id: params[:id], steam_id: params[:user_inventory_steam_id])

        log.destroy!
        render json: { message: "Deleted" }, status: :ok
      end
    end
  end
end
