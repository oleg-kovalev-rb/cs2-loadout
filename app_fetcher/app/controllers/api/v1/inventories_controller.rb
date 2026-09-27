# typed: strict

module Api
  module V1
    class InventoriesController < ApplicationController
      extend T::Sig

      WARMUP_CAP = T.let(20, Integer)
      WARMUP_DEDUP_TTL = T.let(90.seconds, ActiveSupport::Duration)

      sig { void }
      def show
        items_names = UserInventoryCache.read(current_steam_id)

        unless items_names
          client = Steam::Client.new
          response = client.fetch_user_inventory(current_steam_id)

          unless response.success?
            render json: { message: response.error }, status: :bad_request
            return
          end

          items_names = response.data.market_hash_names
          UserInventoryCache.write(current_steam_id, items_names)
        end

        items = ItemPriceCache.fetch_for(items_names)

        missing_names = items_names - items.keys
        save_missing_items(missing_names)

        new_items = missing_names.map do |name|
          attrs = Steam::ItemParser.parse(name)
          Item.new(attrs)
        end

        inventory_items = items.values + new_items

        enqueue_price_warmup(items.values)

        render json: {
          items_count: inventory_items.size,
          items: inventory_items.as_json(only: [
            :market_hash_name,
            :metadata,
            :current_price_cents,
            :change_24h_cents
          ])
        }, status: :ok
      end

      private

      sig { params(names: T::Array[String]).void }
      def save_missing_items(names)
        names.each_slice(500) do |names_batch|
          ItemsListUpdateWorker.perform_async(names_batch)
        end
      end

      sig { params(items: T::Array[Item]).void }
      def enqueue_price_warmup(items)
        items.select { |item| item.current_price_cents.nil? }.first(WARMUP_CAP).each do |item|
          dedup_key = "price_warmup_pending:#{item.id}"
          next unless Rails.cache.write(dedup_key, true, unless_exist: true, expires_in: WARMUP_DEDUP_TTL)

          PriceUpdateWorker.perform_async(item.id)
        end
      end
    end
  end
end
