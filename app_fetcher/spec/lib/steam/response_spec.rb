require "rails_helper"

RSpec.describe Steam::Response do
  def response(status)
    described_class[T.untyped].new(status: status, data: nil, error: nil)
  end

  describe "#success?" do
    it "is true only for a 200 status" do
      aggregate_failures do
        expect(response(200).success?).to be(true)
        expect(response(404).success?).to be(false)
      end
    end
  end

  describe "#not_found?" do
    it "is true only for a 404 status" do
      aggregate_failures do
        expect(response(404).not_found?).to be(true)
        expect(response(200).not_found?).to be(false)
        expect(response(429).not_found?).to be(false)
        expect(response(500).not_found?).to be(false)
      end
    end
  end
end
