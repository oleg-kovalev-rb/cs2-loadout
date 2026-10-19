# typed: strict

module Api
  module Public
    class ItemsController < BaseController
      extend T::Sig

      sig { void }
      def index
        payload = ItemListCache.read(params)

        if payload.nil?
          catalog = ItemListQuery.call(params)
          payload = ItemListSerializer.call(catalog)
          ItemListCache.write(params, payload)
        end

        render json: payload, status: :ok if stale?(etag: payload[:meta][:last_synced_at], public: true)
      end
    end
  end
end
