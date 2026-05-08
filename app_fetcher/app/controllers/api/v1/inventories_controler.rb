# typed: strict

module Api
  module V1
    class InventoriesController < ApplicationController
      sig { void }
      def show
        steam_id = params[:steam_id]
        client = Steam::Client.new

        response = client.fetch_user_inventory(steam_id)

        if response.success?
          names = response.data.market_hash_names

          items_attributes = names.map { |name| Steam::ItemBuilder.build(name) }

          unless items_attributes.empty?
            Item.upsert_all(items_attributes, unique_by: :market_hash_name)
          end

          render json: {
            items_count: items.size,
            items: items.as_json(only: [:market_hash_name, :item_type, :metadata]) 
          }, status: :ok
        else
          render json: { message: response.error }, status: :bad_request
        end
      end
    end
  end
end
