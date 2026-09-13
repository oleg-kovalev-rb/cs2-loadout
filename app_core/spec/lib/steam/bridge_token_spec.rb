require "rails_helper"

RSpec.describe Steam::BridgeToken do
  describe ".encode" do
    it "carries the steam_id, verifiable with the same secret" do
      token = described_class.encode("76561198000000001")

      payload, = JWT.decode(token, ENV.fetch("APP_BRIDGE_JWT_SECRET"), true, algorithm: "HS256")

      expect(payload["steam_id"]).to eq("76561198000000001")
      expect(payload["exp"]).to be_within(5).of(2.minutes.from_now.to_i)
    end

    it "is not verifiable with the wrong secret" do
      token = described_class.encode("76561198000000001")

      expect {
        JWT.decode(token, "wrong-secret", true, algorithm: "HS256")
      }.to raise_error(JWT::VerificationError)
    end
  end
end
