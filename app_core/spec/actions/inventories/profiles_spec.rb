require "rails_helper"

RSpec.describe Inventories::Profiles do
  describe ".call" do
    it "maps each requested steam_id that exists to its nickname/avatar_url" do
      create(:user, steam_id: "76561198111111111", nickname: "Ada", avatar_url: "https://example.com/a.jpg")
      create(:user, steam_id: "76561198222222222", nickname: "Grace", avatar_url: nil)

      profiles = described_class.call(%w[76561198111111111 76561198222222222])

      expect(profiles).to eq(
        "76561198111111111" => { nickname: "Ada", avatar_url: "https://example.com/a.jpg" },
        "76561198222222222" => { nickname: "Grace", avatar_url: nil }
      )
    end

    it "omits requested steam_ids with no app_core user" do
      create(:user, steam_id: "76561198111111111", nickname: "Ada", avatar_url: "https://example.com/a.jpg")

      profiles = described_class.call(%w[76561198111111111 76561198333333333])

      expect(profiles.keys).to eq([ "76561198111111111" ])
    end

    it "de-duplicates repeated steam_ids" do
      create(:user, steam_id: "76561198111111111", nickname: "Ada", avatar_url: nil)

      profiles = described_class.call(%w[76561198111111111 76561198111111111])

      expect(profiles.keys).to eq([ "76561198111111111" ])
    end

    it "drops blank steam_ids" do
      create(:user, steam_id: "76561198111111111", nickname: "Ada", avatar_url: nil)

      profiles = described_class.call([ "76561198111111111", "", nil ])

      expect(profiles.keys).to eq([ "76561198111111111" ])
    end

    it "caps the requested steam_ids at 100" do
      steam_ids = Array.new(101) { |n| format("cap-%03d", n) }
      steam_ids.each { |steam_id| create(:user, steam_id: steam_id) }

      profiles = described_class.call(steam_ids)

      expect(profiles.keys).to eq(steam_ids.first(100))
    end

    it "returns an empty map for an empty steam_id list" do
      expect(described_class.call([])).to eq({})
    end
  end
end
