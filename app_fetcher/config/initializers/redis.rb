# typed: strict

require 'redis'
require 'connection_pool'

pool_size = ENV.fetch("RAILS_MAX_THREADS", 5).to_i

if defined?(Sidekiq) && Sidekiq.server?
  pool_size = ENV.fetch("SIDEKIQ_CONCURRENCY", 5).to_i
end

STREAM_REDIS_POOL = ConnectionPool.new(size: pool_size, timeout: 5) do
  Redis.new(url: ENV.fetch("REDIS_URL_STREAM", "redis://localhost:6379/2"))
end
