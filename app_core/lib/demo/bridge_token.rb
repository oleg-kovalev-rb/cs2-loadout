# typed: strict

require "jwt"

module Demo
  class BridgeToken
    extend T::Sig

    ALGORITHM = T.let("HS256", String)
    AUDIENCE = T.let("demo", String)

    sig { params(session: SessionStore::Session).returns(String) }
    def self.encode(session)
      expires_at = session.created_at + SessionStore::TTL_SECONDS.seconds

      payload = {
        demo_id: session.id,
        seed: session.seed,
        aud: AUDIENCE,
        iat: Time.current.to_i,
        exp: expires_at.to_i
      }

      JWT.encode(payload, ENV.fetch("APP_DEMO_JWT_SECRET"), ALGORITHM)
    end
  end
end
