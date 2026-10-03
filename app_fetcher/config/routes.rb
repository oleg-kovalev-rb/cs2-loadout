Rails.application.routes.draw do
  # Define your application routes per the DSL in https://guides.rubyonrails.org/routing.html

  # Reveal health status on /up that returns 200 if the app boots with no exceptions, otherwise 500.
  # Can be used by load balancers and uptime monitors to verify that the app is live.
  get "up" => "rails/health#show", as: :rails_health_check

  # Defines the root path route ("/")
  # root "posts#index"

  namespace :api do
    namespace :v1 do
      get "inventories/me", to: "inventories#show"
      post "inventories/refresh", to: "inventories#refresh"
      get "inventory_values", to: "inventory_values#index"
      get "item_prices/dynamics", to: "item_prices#dynamics"
      get "item_prices/trend", to: "item_prices#trend"
      get "item_prices/:market_hash_name/history", to: "item_prices#history"
    end
  end
end
