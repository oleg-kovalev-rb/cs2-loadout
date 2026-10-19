# typed: strict

module Api
  module V1
    class InventoriesController < BaseController
      extend T::Sig

      sig { void }
      def show
        items = UserInventoryCache.fetch(current_steam_id)

        if items
          render_inventory(items)
        else
          render_resolved(UserInventorySyncService.call(current_steam_id))
        end
      end

      private

      sig { params(result: ServiceResult[T::Array[Item]]).void }
      def render_resolved(result)
        unless result.success?
          render json: { message: result.error }, status: :bad_request
          return
        end

        render_inventory(T.must(result.data))
      end

      sig { params(items: T::Array[Item]).void }
      def render_inventory(items)
        render json: InventorySerializer.call(items), status: :ok
      end
    end
  end
end
