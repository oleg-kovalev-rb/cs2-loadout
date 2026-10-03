# typed: strict

module Api
  module V1
    class ItemPricesController < ApplicationController
      extend T::Sig

      WARMUP_CAP = T.let(20, Integer)
      WARMUP_DEDUP_TTL = T.let(90.seconds, ActiveSupport::Duration)
      ALLOWED_PERIODS = T.let(
        [ PricePeriod::TwentyFourHours, PricePeriod::SevenDays, PricePeriod::ThirtyDays, PricePeriod::OneYear, PricePeriod::All ].freeze,
        T::Array[PricePeriod]
      )

      sig { void }
      def dynamics
        names = owned_market_hash_names
        priced_items = ItemPriceCache.fetch_for(names)
        enqueue_price_warmup(priced_items.values)

        result = priced_items.each_with_object({}) do |(name, item), hash|
          next if item.current_price_cents.nil?

          change = item.change_24h_cents || 0
          base = item.current_price_cents - change
          percent = base.zero? ? 0.0 : (change.to_f / base * 100).round(2)

          hash[name] = {
            current_price_cents: item.current_price_cents,
            change_24h_cents: change,
            change_24h_percent: percent
          }
        end

        render json: result, status: :ok
      end

      sig { void }
      def trend
        render json: ItemTrendCache.fetch_for(owned_market_hash_names), status: :ok
      end

      sig { void }
      def history
        period = PricePeriod.try_deserialize(params[:period].presence || "30d")

        unless period && ALLOWED_PERIODS.include?(period)
          render json: { message: "Unsupported period: #{params[:period]}" }, status: :bad_request
          return
        end

        item = Item.find_by(market_hash_name: params[:market_hash_name])

        unless item
          render json: [], status: :ok
          return
        end

        points = if period == PricePeriod::ThirtyDays
          PriceHistoryCache.fetch_for([ item.market_hash_name ])[item.market_hash_name] || []
        else
          since = period.duration&.ago
          PriceLog.where(item_id: item.id, created_at: since..).order(:created_at).map do |log|
            { at: log.created_at.iso8601, price_cents: log.lowest_price_cents, volume: log.volume }
          end
        end

        render json: points, status: :ok
      end

      private

      sig { returns(T::Array[String]) }
      def owned_market_hash_names
        (UserInventoryCache.fetch(current_steam_id) || []).map(&:market_hash_name)
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
