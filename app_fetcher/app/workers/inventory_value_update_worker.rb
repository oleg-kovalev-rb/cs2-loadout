# typed: strict

class InventoryValueUpdateWorker
  include Sidekiq::Worker
  extend T::Sig

  sidekiq_options queue: :default, retry: 3

  sig { params(steam_id: String).void }
  def perform(steam_id)
    InventoryValueRecordingService.new(steam_id).call!
  end
end
