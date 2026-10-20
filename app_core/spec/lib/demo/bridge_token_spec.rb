require "rails_helper"

RSpec.describe Demo::BridgeToken do
  let(:session) do
    Demo::SessionStore::Session.new(
      id: "demo-1",
      seed: 42,
      created_at: Time.current
    )
  end

  describe ".encode" do
    it "carries the demo id, seed, audience, and a 12-hour expiry" do
      token = described_class.encode(session)

      payload, = JWT.decode(token, ENV.fetch("APP_DEMO_JWT_SECRET"), true, algorithm: "HS256")

      aggregate_failures do
        expect(payload["demo_id"]).to eq("demo-1")
        expect(payload["seed"]).to eq(42)
        expect(payload["aud"]).to eq("demo")
        expect(payload["exp"]).to be_within(5).of(12.hours.from_now.to_i)
      end
    end

    it "is not verifiable with the player bridge secret" do
      token = described_class.encode(session)

      expect {
        JWT.decode(token, ENV.fetch("APP_BRIDGE_JWT_SECRET"), true, algorithm: "HS256")
      }.to raise_error(JWT::VerificationError)
    end
  end
end
