# typed: strict

require "jwt"

module Steam
  class BridgeToken
    extend T::Sig

    ALGORITHM = T.let("HS256", String)
    TTL = T.let(8.hours, ActiveSupport::Duration)

    sig { params(steam_id: String).returns(String) }
    def self.encode(steam_id)
      payload = { steam_id: steam_id, exp: TTL.from_now.to_i, iat: Time.now.to_i }
      JWT.encode(payload, ENV.fetch("APP_BRIDGE_JWT_SECRET"), ALGORITHM)
    end
  end
end
