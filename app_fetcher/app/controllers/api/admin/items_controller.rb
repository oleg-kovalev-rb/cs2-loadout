# typed: strict

module Api
  module Admin
    class ItemsController < BaseController
      extend T::Sig

      sig { void }
      def index
        pagination = Appliers::Pagination.new(params[:page], params[:per_page])
        total_count = Item.count
        items = pagination.apply(Item.order(id: :asc))

        render json: ::Admin::ItemSerializer.call_for_list(pagination_meta(pagination, total_count), items), status: :ok
      end

      sig { void }
      def show
        item = Item.find(params[:id])

        render json: ::Admin::ItemSerializer.call(item), status: :ok
      end

      sig { void }
      def create
        item = Item.new(market_hash_name: create_params[:market_hash_name])

        if item.save
          PriceUpdateWorker.perform_async(item.id)
          render json: ::Admin::ItemSerializer.call(item), status: :created
        else
          render json: { message: item.errors.full_messages.to_sentence }, status: :unprocessable_content
        end
      end

      sig { void }
      def destroy
        item = Item.find(params[:id])

        item.destroy!
        render json: { message: "Deleted" }, status: :ok
      end

      sig { void }
      def refresh_price
        item = Item.find(params[:id])

        PriceUpdateWorker.perform_async(item.id)
        render json: { message: "Price refresh enqueued" }, status: :accepted
      end

      sig { void }
      def warm_cache
        item = Item.find(params[:id])

        warm_item_caches([ item.market_hash_name ])
        render json: { message: "Cache warmed" }, status: :ok
      end

      sig { void }
      def bulk_warm_cache
        items = Item.where(id: Array(params[:item_ids]))
        warm_item_caches(items.pluck(:market_hash_name))

        render json: {
          warmed_item_ids: items.pluck(:id),
          message: "Cache warmed for #{items.size} item(s)"
        }, status: :ok
      end

      sig { void }
      def warm_catalog_cache
        catalog = ItemListQuery.call(params)
        ItemListCache.write(params, ItemListSerializer.call(catalog))

        render json: { message: "Catalog cache warmed" }, status: :ok
      end

      private

      sig { params(market_hash_names: T::Array[String]).void }
      def warm_item_caches(market_hash_names)
        ItemPriceCache.fetch_for(market_hash_names)
        PriceHistoryCache.fetch_for(market_hash_names)
        ItemTrendCache.fetch_for(market_hash_names)
      end

      sig { returns(ActionController::Parameters) }
      def create_params
        params.require(:item).permit(:market_hash_name)
      end
    end
  end
end
