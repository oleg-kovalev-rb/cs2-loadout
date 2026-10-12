module AdminBridgeTokenHelper
  def admin_bridge_token_for(admin_id)
    JWT.encode({ admin_id: admin_id, exp: 2.minutes.from_now.to_i }, ENV.fetch("APP_ADMIN_BRIDGE_JWT_SECRET"), "HS256")
  end
end

RSpec.configure do |config|
  config.include AdminBridgeTokenHelper, type: :request
end
