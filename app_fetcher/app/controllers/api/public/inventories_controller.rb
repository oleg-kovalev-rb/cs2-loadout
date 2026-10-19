# typed: strict

module Api
  module Public
    class InventoriesController < BaseController
      extend T::Sig

      sig { void }
      def index
        payload = InventoryCatalogCache.read(params)

        if payload.nil?
          page = InventoryCatalogQuery.call(params)
          payload = InventoryCatalogSerializer.call(page)
          InventoryCatalogCache.write(params, payload)
        end

        render json: payload, status: :ok if stale?(etag: payload, public: true)
      end

      sig { void }
      def show
        steam_id = params[:steam_id].to_s
        payload = InventoryDetailCache.read(steam_id, params)

        if payload.nil?
          page = InventoryDetailQuery.call(steam_id, params)
          payload = InventoryDetailSerializer.call(page)
          InventoryDetailCache.write(steam_id, params, payload)
        end

        render json: payload, status: :ok if stale?(etag: payload, public: true)
      end
    end
  end
end
