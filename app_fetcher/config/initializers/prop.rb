require "prop"
require "redis"

ActiveSupport.on_load(:after_initialize) do
  Prop.cache = Rails.cache

  Prop.configure(:steam_price_api, threshold: 20,   interval: 1.minute)
  Prop.configure(:steam_price_api, threshold: 1000, interval: 1.day)

  Prop.configure(:steam_history_api, threshold: 5,   interval: 1.minute)
  Prop.configure(:steam_history_api, threshold: 500, interval: 1.day)

  Prop.configure(:steam_assets_api, threshold: 30, interval: 1.minute)
end