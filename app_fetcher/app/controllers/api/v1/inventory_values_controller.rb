# typed: strict

module Api
  module V1
    class InventoryValuesController < BaseController
      extend T::Sig

      sig { void }
      def index
        value = InventoryValueHistoryQuery.call(current_steam_id, params)

        render json: InventoryValueSerializer.call(value), status: :ok
      end
    end
  end
end
