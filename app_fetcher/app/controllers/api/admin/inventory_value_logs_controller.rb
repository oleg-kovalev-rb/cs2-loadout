# typed: strict

module Api
  module Admin
    class InventoryValueLogsController < ApplicationController
      extend T::Sig

      sig { void }
      def index
        logs = InventoryValueLog.where(steam_id: params[:user_inventory_steam_id])

        render json: { inventory_value_logs: logs.map { |log| inventory_value_log_json(log) } }, status: :ok
      end

      sig { void }
      def destroy
        log = InventoryValueLog.find_by!(id: params[:id], steam_id: params[:user_inventory_steam_id])

        log.destroy!
        render json: { message: "Deleted" }, status: :ok
      end

      private

      sig { params(log: InventoryValueLog).returns(T::Hash[Symbol, T.untyped]) }
      def inventory_value_log_json(log)
        {
          id: log.id,
          log_date: log.log_date.iso8601,
          total_value_cents: log.total_value_cents
        }
      end
    end
  end
end
