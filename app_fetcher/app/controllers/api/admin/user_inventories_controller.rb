# typed: strict

module Api
  module Admin
    class UserInventoriesController < ApplicationController
      extend T::Sig

      sig { void }
      def index
        render json: {
          user_inventories: UserInventory.all.map { |user_inventory| user_inventory_json(user_inventory) }
        }, status: :ok
      end

      sig { void }
      def show
        user_inventory = UserInventory.find_by!(steam_id: params[:steam_id])

        render json: { user_inventory: user_inventory_json(user_inventory) }, status: :ok
      end

      sig { void }
      def destroy
        user_inventory = UserInventory.find_by!(steam_id: params[:steam_id])

        user_inventory.destroy!
        render json: { message: "Deleted" }, status: :ok
      end

      sig { void }
      def sync
        result = UserInventorySyncService.call(params[:steam_id].to_s)

        unless result.success
          render json: { message: result.error }, status: :bad_request
          return
        end

        render json: { message: "Inventory synced" }, status: :ok
      end

      sig { void }
      def warm_cache
        UserInventoryCache.fetch(params[:steam_id].to_s)
        render json: { message: "Cache warmed" }, status: :ok
      end

      private

      sig { params(user_inventory: UserInventory).returns(T::Hash[Symbol, T.untyped]) }
      def user_inventory_json(user_inventory)
        {
          steam_id: user_inventory.steam_id,
          items_count: user_inventory.items.size,
          created_at: user_inventory.created_at.iso8601,
          updated_at: user_inventory.updated_at.iso8601
        }
      end
    end
  end
end
