require "rails_helper"

RSpec.describe ServiceResult do
  let(:payload) { create(:item, current_price_cents: 100) }

  describe "predicates" do
    it "reports a successful call via success?" do
      result = described_class[Item].new(status: ServiceResult::Status::Ok, data: payload, error: nil)

      aggregate_failures do
        expect(result.success?).to be(true)
        expect(result.skipped?).to be(false)
        expect(result.failed?).to be(false)
        expect(result.data).to eq(payload)
        expect(result.error).to be_nil
      end
    end

    it "reports a deliberately declined call via skipped?" do
      result = described_class[Item].new(status: ServiceResult::Status::Skipped, data: nil, error: nil)

      aggregate_failures do
        expect(result.success?).to be(false)
        expect(result.skipped?).to be(true)
        expect(result.failed?).to be(false)
        expect(result.data).to be_nil
        expect(result.error).to be_nil
      end
    end

    it "reports an expected failure via failed?" do
      result = described_class[Item].new(status: ServiceResult::Status::Failed, data: nil, error: "boom")

      aggregate_failures do
        expect(result.success?).to be(false)
        expect(result.skipped?).to be(false)
        expect(result.failed?).to be(true)
        expect(result.data).to be_nil
        expect(result.error).to eq("boom")
      end
    end
  end
end
