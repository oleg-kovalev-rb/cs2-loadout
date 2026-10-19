# typed: strict

module Api
  module V1
    class InventoriesController < BaseController
      extend T::Sig

      sig { void }
      def show
        items = UserInventoryCache.fetch(current_steam_id)

        if items
          render json: InventorySerializer.call(items), status: :ok
        else
          items_sync_result = UserInventorySyncService.call(current_steam_id)

          if items_sync_result.success?
            render json: InventorySerializer.call(T.must(items_sync_result.data)), status: :ok
          else
            render json: { message: items_sync_result.error }, status: :bad_request
          end
        end
      end
    end
  end
end
