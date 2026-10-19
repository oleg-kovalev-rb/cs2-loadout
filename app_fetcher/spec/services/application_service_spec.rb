require "rails_helper"

RSpec.describe ApplicationService do
  let(:payload) { "payload" }

  describe "result helpers" do
    it "builds a Success result around the payload" do
      result = described_class.send(:success, payload)

      aggregate_failures do
        expect(result.success?).to be(true)
        expect(result.skipped?).to be(false)
        expect(result.failed?).to be(false)
        expect(result.data).to eq(payload)
        expect(result.error).to be_nil
      end
    end

    it "builds a Skipped result with no payload or error" do
      result = described_class.send(:skipped)

      aggregate_failures do
        expect(result.success?).to be(false)
        expect(result.skipped?).to be(true)
        expect(result.failed?).to be(false)
        expect(result.data).to be_nil
        expect(result.error).to be_nil
      end
    end

    it "builds a Failure result carrying the error" do
      result = described_class.send(:failure, "boom")

      aggregate_failures do
        expect(result.success?).to be(false)
        expect(result.skipped?).to be(false)
        expect(result.failed?).to be(true)
        expect(result.data).to be_nil
        expect(result.error).to eq("boom")
      end
    end
  end

  it "keeps the helpers out of the public service interface" do
    aggregate_failures do
      expect(described_class).not_to respond_to(:success)
      expect(described_class).not_to respond_to(:failure)
      expect(described_class).not_to respond_to(:skipped)
    end
  end
end
