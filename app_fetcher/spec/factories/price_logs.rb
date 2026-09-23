FactoryBot.define do
  factory :price_log do
    item
    lowest_price_cents { 3845 }
    median_price_cents { 3900 }
    volume { 512 }

    trait :old do
      created_at { 25.hours.ago }
    end
  end
end
