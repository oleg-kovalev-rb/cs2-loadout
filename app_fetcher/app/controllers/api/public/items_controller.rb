# typed: strict

module Api
  module Public
    class ItemsController < ApplicationController
      extend T::Sig

      sig { void }
      def index
        payload = ItemCatalogCache.read(params)
        if payload.nil?
          page = ItemCatalogQuery.call(params)
          payload = ItemCatalogSerializer.call(page)
          ItemCatalogCache.write(params, payload)
        end

        render json: payload, status: :ok if stale?(etag: payload[:meta][:last_synced_at], public: true)
      end
    end
  end
end
