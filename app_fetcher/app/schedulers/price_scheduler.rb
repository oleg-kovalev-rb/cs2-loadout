# typed: strict

class PriceScheduler
  include Sidekiq::Worker
  extend T::Sig

  sidekiq_options queue: :default, retry: 3

  sig { void }
  def perform
    Item.due_for_price_update.find_each do |item|
      PriceUpdateWorker.perform_async(item.id)
    end
  end
end
