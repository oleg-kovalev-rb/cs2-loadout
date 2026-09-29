FactoryBot.define do
  factory :inventory_value_log do
    sequence(:steam_id) { |n| "7656119800000#{n}" }
    log_date { Date.current }
    total_value_cents { 3845 }
  end
end
