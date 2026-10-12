require "rails_helper"

RSpec.describe Admin::BridgeToken do
  describe ".encode" do
    it "carries the admin_id, verifiable with the same secret" do
      token = described_class.encode("42")

      payload, = JWT.decode(token, ENV.fetch("APP_ADMIN_BRIDGE_JWT_SECRET"), true, algorithm: "HS256")

      expect(payload["admin_id"]).to eq("42")
      expect(payload["exp"]).to be_within(5).of(8.hours.from_now.to_i)
    end

    it "is not verifiable with the wrong secret" do
      token = described_class.encode("42")

      expect {
        JWT.decode(token, "wrong-secret", true, algorithm: "HS256")
      }.to raise_error(JWT::VerificationError)
    end

    it "is not verifiable with the per-player bridge token secret" do
      token = described_class.encode("42")

      expect {
        JWT.decode(token, ENV.fetch("APP_BRIDGE_JWT_SECRET"), true, algorithm: "HS256")
      }.to raise_error(JWT::VerificationError)
    end
  end
end
