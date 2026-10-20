module DemoSessionHelper
  def clear_demo_redis
    DEMO_REDIS_POOL.with { |redis| redis.flushdb }
  end

  def start_demo
    post demo_session_path
  end

  def demo_session_keys
    DEMO_REDIS_POOL.with { |redis| redis.keys("demo:session:*") }
  end
end

RSpec.configure do |config|
  config.include DemoSessionHelper, type: :request
  config.before(:each, :demo_redis) { clear_demo_redis }
end
