FactoryBot.define do
  factory :user do
    sequence(:steam_id) { |n| "7656119800000#{n}" }
    nickname { "Player" }
    avatar_url { "https://example.com/avatar.jpg" }
  end
end
