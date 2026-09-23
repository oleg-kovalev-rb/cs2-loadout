module RedisStreamHelper
  PRICES_STREAM_KEY = "prices_stream"

  def flush_prices_stream
    STREAM_REDIS_POOL.with { |redis| redis.xtrim(PRICES_STREAM_KEY, 0) }
  end

  def prices_stream_entries
    STREAM_REDIS_POOL.with { |redis| redis.xrange(PRICES_STREAM_KEY, "-", "+") }
  end
end

RSpec.configure do |config|
  config.include RedisStreamHelper
end
