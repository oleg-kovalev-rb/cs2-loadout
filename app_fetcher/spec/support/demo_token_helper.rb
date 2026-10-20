module DemoTokenHelper
  def demo_token(seed: 42, aud: "demo", exp: 1.hour.from_now.to_i)
    JWT.encode(
      { demo_id: "demo-1", seed: seed, aud: aud, exp: exp },
      ENV.fetch("APP_DEMO_JWT_SECRET"),
      "HS256"
    )
  end
end

RSpec.configure do |config|
  config.include DemoTokenHelper, type: :request
end
