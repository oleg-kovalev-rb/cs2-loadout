# typed: strict

module Api
  module V1
    class InventoryValuesController < BaseController
      extend T::Sig

      sig { void }
      def index
        page = InventoryValueHistoryQuery.call(current_steam_id, params)

        render json: InventoryValuationSerializer.call(page), status: :ok
      end
    end
  end
end
