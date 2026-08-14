# typed: strict

class PriceScheduler
  include Sidekiq::Worker
  extend T::Sig

  sidekiq_options queue: :default

  sig { void }
  def perform
    items_to_update = Item.where("updated_at < ? OR current_price_cents IS NULL", 1.hour.ago)

    items_to_update.find_each do |item|
      PriceUpdateWorker.perform_async(item.id)
    end
  end
end
