# typed: strict

class InventoryValueScheduler
  include Sidekiq::Worker
  extend T::Sig

  sidekiq_options queue: :default

  sig { void }
  def perform
    InventoryValueLog.distinct.pluck(:steam_id).each do |steam_id|
      InventoryValueUpdateWorker.perform_async(steam_id)
    end
  end
end
