# typed: strict

module Api
  module V1
    class InventoryValuesController < BaseController
      extend T::Sig

      sig { void }
      def index
        period = PricePeriod.resolve(
          params[:period], supported: InventoryValueLog::SUPPORTED_PERIODS, default: PricePeriod::All
        )

        raise Api::V1::UnsupportedParamError, "Unsupported period: #{params[:period]}" unless period

        seed_if_empty
        page = InventoryValuation.page(current_steam_id, period)

        render json: InventoryValuationSerializer.call(page), status: :ok
      end

      private

      sig { void }
      def seed_if_empty
        return unless InventoryValueLog.where(steam_id: current_steam_id).empty?

        InventoryValueRecordingService.call(current_steam_id)
      end
    end
  end
end
