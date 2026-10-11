FactoryBot.define do
  factory :item do
    sequence(:market_hash_name) { |n| "AK-47 | Factory Test #{n} (Field-Tested)" }
    current_price_cents { 3845 }
    change_24h_cents { 0 }
    metadata { { marketable: true, category: "Rifles" } }

    trait :stale do
      updated_at { 2.hours.ago }
    end

    trait :without_price do
      current_price_cents { nil }
    end

    trait :non_marketable do
      metadata { { marketable: false } }
    end
  end
end
