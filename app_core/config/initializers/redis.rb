# typed: strict

require "redis"
require "connection_pool"

DEMO_REDIS_POOL = T.let(
  ConnectionPool.new(size: ENV.fetch("RAILS_MAX_THREADS", 5).to_i, timeout: 5) do
    Redis.new(url: ENV.fetch("REDIS_URL_DEMO", "redis://localhost:6379/3"))
  end,
  ConnectionPool
)
