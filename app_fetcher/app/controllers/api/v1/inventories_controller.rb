# typed: strict

module Api
  module V1
    class InventoriesController < ApplicationController
      extend T::Sig

      sig { void }
      def show
        steam_id = params[:steam_id]
        client = Steam::Client.new

        response = client.fetch_user_inventory(steam_id)

        if response.success?
          items_names = response.data.market_hash_names

          items = Item.where(market_hash_name: items_names).index_by(&:market_hash_name)

          missing_names = items_names - items.keys
          save_missing_items(missing_names)

          new_items = missing_names.map do |name|
            attrs = Steam::ItemParser.parse(name)
            Item.new(attrs)
          end

          inventory_items = items + new_items

          render json: {
            items_count: inventory_items.size,
            items: inventory_items.as_json(only: [
              :market_hash_name,
              :item_type,
              :metadata,
              :current_price_cents,
              :change_24h_cents
            ]) 
          }, status: :ok
        else
          render json: { message: response.error }, status: :bad_request
        end
      end

      private

      def save_missing_items(names)
        names.each_slice(500) do |names_batch|
          ItemsListUpdateWorker.perform_async(names_batch)
        end
      end
    end
  end
end
