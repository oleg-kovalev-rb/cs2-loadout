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
      get "inventory_values", to: "inventory_values#index"
      get "item_prices/dynamics", to: "item_prices#dynamics"
      get "item_prices/trend", to: "item_prices#trend"
      get "item_prices/:market_hash_name/history", to: "item_prices#history"
    end

    namespace :public do
      get "items", to: "items#index"
      get "inventories", to: "inventories#index"
      get "inventories/:steam_id", to: "inventories#show"
    end

    namespace :admin do
      get "price_logs", to: "price_logs#index"
      get "inventory_value_logs", to: "inventory_value_logs#index"

      resources :items, only: %i[index show create destroy] do
        collection do
          post :bulk_warm_cache
          post :warm_catalog_cache
        end

        member do
          post :refresh_price
          post :warm_cache
        end

        resources :price_logs, only: %i[destroy]
      end

      resources :user_inventories, only: %i[index show destroy], param: :steam_id do
        collection do
          post :bulk_warm_cache
        end

        member do
          post :sync
          post :warm_cache
        end

        resources :inventory_value_logs, only: %i[destroy]
      end
    end
  end
end
