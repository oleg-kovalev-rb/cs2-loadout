# typed: strict

class UserInventorySyncWorker
  include Sidekiq::Worker
  extend T::Sig

  sidekiq_options queue: :prices, retry: 5

  sig { params(steam_id: String).void }
  def perform(steam_id)
    result = UserInventorySyncService.call(steam_id)
    return if result.success

    Rails.logger.warn("[UserInventorySyncWorker] Failed for #{steam_id}: #{result.error}")
  end
end
