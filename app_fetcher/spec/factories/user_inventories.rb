FactoryBot.define do
  factory :user_inventory do
    sequence(:steam_id) { |n| "7656119800000#{n}" }
  end
end
