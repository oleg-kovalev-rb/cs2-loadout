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

    if response.success?
      price_log = Steam::PriceLogBuilder.build(item_id, response.data)

      Item.transaction do
        price_log.save!
        item.update!(current_price_cents: price_log.lowest_price_cents)
      end

      price_24h_ago = item.price_logs
                    .where("created_at <= ?", 24.hours.ago)
                    .order(created_at: :desc)
                    .first

      change_24h_cents = (price_log.lowest_price_cents - price_24h_ago.lowest_price_cents).to_i

      publish_to_stream(
        item.market_hash_name,
        price_log.lowest_price_cents
        change_24h_cents
      )
    else
      Rails.logger.warn("[PriceUpdateWorker] Failed for #{item.market_hash_name}: #{response.error}")
    end
  end

  private

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
