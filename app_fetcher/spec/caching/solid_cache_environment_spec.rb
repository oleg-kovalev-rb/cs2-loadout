require "rails_helper"

RSpec.describe "solid_cache environment" do
  it "writes, reads, and deletes through the real solid_cache-backed store" do
    Rails.cache.write("environment_smoke_test", "ok")

    aggregate_failures do
      expect(Rails.cache.read("environment_smoke_test")).to eq("ok")
      expect(Rails.cache).to be_a(SolidCache::Store)

      Rails.cache.delete("environment_smoke_test")
      expect(Rails.cache.read("environment_smoke_test")).to be_nil
    end
  end

  it "clears all entries via Rails.cache.clear" do
    Rails.cache.write("another_smoke_key", "value")

    Rails.cache.clear

    expect(Rails.cache.read("another_smoke_key")).to be_nil
  end
end
