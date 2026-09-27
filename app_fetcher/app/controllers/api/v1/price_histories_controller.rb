# typed: strict

module Api
  module V1
    class PriceHistoriesController < ApplicationController
      extend T::Sig

      sig { void }
      def index
        names = Array(params[:market_hash_names])

        if params[:since].present?
          since = Time.iso8601(params[:since])

          items = Item.where(market_hash_name: names)
          logs_by_item = PriceLog.where(item_id: items.select(:id), created_at: since..)
                                  .order(:created_at)
                                  .group_by(&:item_id)

          render json: {
            items: items.map do |item|
              {
                market_hash_name: item.market_hash_name,
                points: (logs_by_item[item.id] || []).map do |log|
                  { at: log.created_at.iso8601, price_cents: log.lowest_price_cents, volume: log.volume }
                end
              }
            end
          }, status: :ok
        else
          points_by_name = PriceHistoryCache.fetch_for(names)

          render json: {
            items: points_by_name.map { |market_hash_name, points| { market_hash_name:, points: } }
          }, status: :ok
        end
      end
    end
  end
end
