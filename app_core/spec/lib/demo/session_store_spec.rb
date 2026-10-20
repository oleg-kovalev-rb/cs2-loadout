require "rails_helper"

RSpec.describe Demo::SessionStore do
  before do
    DEMO_REDIS_POOL.with { |redis| redis.flushdb }
  end

  describe ".create" do
    it "stores the demo session as JSON with a 12-hour TTL" do
      session = described_class.create

      raw = DEMO_REDIS_POOL.with { |redis| redis.get("demo:session:#{session.id}") }
      ttl = DEMO_REDIS_POOL.with { |redis| redis.ttl("demo:session:#{session.id}") }
      payload = JSON.parse(raw)

      aggregate_failures do
        expect(session.id).to be_present
        expect(session.seed).to be_a(Integer)
        expect(payload).to include(
          "id" => session.id,
          "seed" => session.seed,
          "created_at" => session.created_at.iso8601
        )
        expect(ttl).to be_within(2).of(described_class::TTL_SECONDS)
      end
    end
  end

  describe ".find" do
    it "round-trips the stored session" do
      session = described_class.create

      found = described_class.find(session.id)

      aggregate_failures do
        expect(found&.id).to eq(session.id)
        expect(found&.seed).to eq(session.seed)
        expect(found&.created_at).to be_within(1.second).of(session.created_at)
      end
    end

    it "returns nil for an unknown id" do
      expect(described_class.find("missing")).to be_nil
    end
  end

  describe ".remaining_seconds" do
    it "returns the remaining TTL for a live session" do
      session = described_class.create

      expect(described_class.remaining_seconds(session.id)).to be_within(2).of(described_class::TTL_SECONDS)
    end

    it "returns nil for an unknown id" do
      expect(described_class.remaining_seconds("missing")).to be_nil
    end
  end

  describe ".delete" do
    it "removes the stored session" do
      session = described_class.create

      described_class.delete(session.id)

      expect(described_class.find(session.id)).to be_nil
    end
  end
end
