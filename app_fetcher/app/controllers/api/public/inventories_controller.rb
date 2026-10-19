# typed: strict

module Api
  module Public
    class InventoriesController < BaseController
      extend T::Sig

      sig { void }
      def index
        payload = InventoryListCache.read(params)

        if payload.nil?
          summaries = InventoryListQuery.call(params)
          payload = InventoryListSerializer.call(summaries)
          InventoryListCache.write(params, payload)
        end

        render json: payload, status: :ok if stale?(etag: payload, public: true)
      end

      sig { void }
      def show
        steam_id = params[:steam_id].to_s
        payload = InventoryDetailCache.read(steam_id, params)

        if payload.nil?
          details = InventoryDetailQuery.call(steam_id, params)
          payload = InventoryDetailSerializer.call(details)
          InventoryDetailCache.write(steam_id, params, payload)
        end

        render json: payload, status: :ok if stale?(etag: payload, public: true)
      end
    end
  end
end
