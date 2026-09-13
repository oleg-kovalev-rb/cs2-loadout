module BridgeTokenHelper
  def bridge_token_for(steam_id)
    JWT.encode({ steam_id: steam_id, exp: 2.minutes.from_now.to_i }, ENV.fetch("APP_BRIDGE_JWT_SECRET"), "HS256")
  end
end

RSpec.configure do |config|
  config.include BridgeTokenHelper, type: :request
end
