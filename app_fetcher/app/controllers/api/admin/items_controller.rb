# typed: strict

module Api
  module Admin
    class ItemsController < ApplicationController
      extend T::Sig

      sig { void }
      def index
        render json: { items: Item.all.map { |item| item_json(item) } }, status: :ok
      end

      sig { void }
      def show
        item = Item.find(params[:id])

        render json: { item: item_json(item) }, status: :ok
      end

      sig { void }
      def create
        item = Item.new(market_hash_name: create_params[:market_hash_name])

        if item.save
          PriceUpdateWorker.perform_async(item.id)
          render json: { item: item_json(item) }, status: :created
        else
          render json: { message: item.errors.full_messages.to_sentence }, status: :unprocessable_content
        end
      end

      sig { void }
      def update
        item = Item.find(params[:id])

        if item.update(update_params)
          render json: { item: item_json(item) }, status: :ok
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

        warm_item_caches(item)
        render json: { message: "Cache warmed" }, status: :ok
      end

      private

      sig { params(item: Item).void }
      def warm_item_caches(item)
        ItemPriceCache.fetch_for([ item.market_hash_name ])
        PriceHistoryCache.fetch_for([ item.market_hash_name ])
        ItemTrendCache.fetch_for([ item.market_hash_name ])
      end

      sig { returns(ActionController::Parameters) }
      def create_params
        params.require(:item).permit(:market_hash_name)
      end

      sig { returns(ActionController::Parameters) }
      def update_params
        params.require(:item).permit(
          :market_hash_name, :weapon_type, :item_name, :condition, :stattrak, :souvenir,
          :icon_url, :marketable, :tradable, :rarity, :category,
          :current_price_cents, :change_24h_cents
        )
      end

      sig { params(item: Item).returns(T::Hash[Symbol, T.untyped]) }
      def item_json(item)
        {
          id: item.id,
          market_hash_name: item.market_hash_name,
          metadata: {
            weapon_type: item.weapon_type,
            item_name: item.item_name,
            condition: item.condition,
            stattrak: item.stattrak,
            souvenir: item.souvenir,
            icon_url: item.icon_url,
            marketable: item.marketable,
            tradable: item.tradable,
            rarity: item.rarity,
            category: item.category
          },
          current_price_cents: item.current_price_cents,
          change_24h_cents: item.change_24h_cents,
          created_at: item.created_at.iso8601,
          updated_at: item.updated_at.iso8601
        }
      end
    end
  end
end
