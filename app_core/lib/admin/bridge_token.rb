# typed: strict

require "jwt"

module Admin
  class BridgeToken
    extend T::Sig

    ALGORITHM = T.let("HS256", String)
    TTL = T.let(8.hours, ActiveSupport::Duration)

    sig { params(admin_id: String).returns(String) }
    def self.encode(admin_id)
      payload = { admin_id: admin_id, exp: TTL.from_now.to_i, iat: Time.now.to_i }
      JWT.encode(payload, ENV.fetch("APP_ADMIN_BRIDGE_JWT_SECRET"), ALGORITHM)
    end
  end
end
