# typed: strict

class PriceUpdateWorker
  include Sidekiq::Worker
  extend T::Sig

  sidekiq_options queue: :prices, retry: 5

  sig { params(item_id: Integer).void }
  def perform(item_id)
    item = Item.find_by(id: item_id)
    return unless item

    client = Steam::Client.new
    response = client.fetch_item_price(item.market_hash_name)

    unless response.success?
      Rails.logger.warn("[PriceUpdateWorker] Failed for #{item.market_hash_name}: #{response.error}")
      return
    end

    updated_item = T.must(PriceUpdateService.call(item, T.must(response.data)).data)
    update_related_cache(updated_item.market_hash_name)

    price = updated_item.current_price_cents
    return if price.nil?

    publish_to_stream(updated_item.market_hash_name, price, updated_item.change_24h_cents || 0)
  end

  private

  sig { params(market_hash_name: String).void }
  def update_related_cache(market_hash_name)
    ItemPriceCache.invalidate(market_hash_name)
    ItemPriceCache.fetch_for([ market_hash_name ])

    PriceHistoryCache.invalidate(market_hash_name)
    PriceHistoryCache.fetch_for([ market_hash_name ])

    ItemTrendCache.invalidate(market_hash_name)
    ItemTrendCache.fetch_for([ market_hash_name ])
  end

  sig { params(market_hash_name: String, price: Integer, change_24h: Integer).void }
  def publish_to_stream(market_hash_name, price, change_24h)
    STREAM_REDIS_POOL.with do |redis|
      redis.xadd(
        "prices_stream",
        {
          market_hash_name: market_hash_name,
          price_cents: price.to_s,
          change_24h_cents: change_24h,
          fetched_at: Time.now.utc.to_i.to_s
        },
        maxlen: 10_000,
        approximate: true
      )
    end
  end
end
