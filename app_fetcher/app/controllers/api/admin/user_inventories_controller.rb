# typed: strict

module Api
  module Admin
    class UserInventoriesController < ApplicationController
      extend T::Sig

      sig { void }
      def index
        pagination = Appliers::Pagination.new(params[:page], params[:per_page])
        total_count = UserInventory.count
        user_inventories = pagination.apply(UserInventory.order(updated_at: :desc)).to_a
        latest_values = latest_value_cents_by_steam_id(user_inventories.map(&:steam_id))
        items_counts = items_count_by_user_inventory_id(user_inventories.map(&:id))

        render json: ::Admin::UserInventorySerializer.call_for_list(
          pagination_meta(pagination, total_count), user_inventories, latest_values: latest_values, items_counts: items_counts
        ), status: :ok
      end

      sig { void }
      def show
        user_inventory = UserInventory.find_by!(steam_id: params[:steam_id])
        total_value_cents = user_inventory.inventory_value_logs.order(log_date: :desc).first&.total_value_cents
        items = user_inventory.user_inventory_items.includes(:item).order(created_at: :desc)

        render json: ::Admin::UserInventorySerializer.call(user_inventory, total_value_cents, user_inventory.items.size, items),
               status: :ok
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

        unless result.success?
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

      sig { void }
      def bulk_warm_cache
        steam_ids = UserInventory.where(steam_id: Array(params[:steam_ids]).map(&:to_s)).pluck(:steam_id)
        steam_ids.each { |steam_id| UserInventoryCache.fetch(steam_id) }

        render json: {
          warmed_steam_ids: steam_ids,
          message: "Cache warmed for #{steam_ids.size} inventory(ies)"
        }, status: :ok
      end

      private

      sig { params(user_inventory_ids: T::Array[Integer]).returns(T::Hash[Integer, Integer]) }
      def items_count_by_user_inventory_id(user_inventory_ids)
        UserInventoryItem.where(user_inventory_id: user_inventory_ids).group(:user_inventory_id).count
      end

      sig { params(steam_ids: T::Array[String]).returns(T::Hash[String, T.nilable(Integer)]) }
      def latest_value_cents_by_steam_id(steam_ids)
        InventoryValueLog
          .where(steam_id: steam_ids)
          .select("DISTINCT ON (steam_id) *")
          .order(:steam_id, log_date: :desc)
          .index_by(&:steam_id)
          .transform_values(&:total_value_cents)
      end
    end
  end
end
