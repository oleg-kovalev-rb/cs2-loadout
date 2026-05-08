require "prop"
require "redis"

ActiveSupport.on_load(:after_initialize) do
  Prop.cache = Rails.cache

  Prop.configure(:steam_price_rpm, threshold: 20,   interval: 1.minute)
  Prop.configure(:steam_price_rpd, threshold: 1000, interval: 1.day)

  Prop.configure(:steam_inventory_rpm, threshold: 20,   interval: 1.minute)
  Prop.configure(:steam_inventory_rpd, threshold: 1000, interval: 1.day)
end
