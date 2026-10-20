FactoryBot.define do
  factory :inventory_value_log do
    sequence(:steam_id) { |n| "7656119800000#{n}" }
    log_date { Date.current }
    total_value_cents { 3845 }
    items_count { 0 }
    pricable_items_count { 0 }
    priced_items_count { 0 }

    trait :complete do
      items_count { 2 }
      pricable_items_count { 2 }
      priced_items_count { 2 }
    end

    trait :partial do
      items_count { 2 }
      pricable_items_count { 2 }
      priced_items_count { 1 }
    end
  end
end
