# typed: strict

module Api
  module V1
    class InventoriesController < ApplicationController
      extend T::Sig

      REFRESH_DEDUP_TTL = T.let(1.day, ActiveSupport::Duration)

      sig { void }
      def show
        items = UserInventoryCache.fetch(current_steam_id)

        if items
          render_inventory(items)
        else
          render_resolved(UserInventorySyncService.call(current_steam_id))
        end
      end

      sig { void }
      def refresh
        dedup_key = "inventory_refresh_pending:#{current_steam_id}"
        unless Rails.cache.write(dedup_key, true, unless_exist: true, expires_in: REFRESH_DEDUP_TTL)
          render json: { message: "Inventory refresh already requested today" }, status: :too_many_requests
          return
        end

        render_resolved(UserInventorySyncService.call(current_steam_id))
      end

      private

      sig { params(result: UserInventorySyncService::Result).void }
      def render_resolved(result)
        unless result.success
          render json: { message: result.error }, status: :bad_request
          return
        end

        render_inventory(T.must(result.items))
      end

      sig { params(items: T::Array[Item]).void }
      def render_inventory(items)
        render json: {
          items_count: items.size,
          items: items.as_json(only: [
            :market_hash_name,
            :metadata
          ])
        }, status: :ok
      end
    end
  end
end
