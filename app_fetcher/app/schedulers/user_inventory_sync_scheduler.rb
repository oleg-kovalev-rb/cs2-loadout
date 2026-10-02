# typed: strict

class UserInventorySyncScheduler
  include Sidekiq::Worker
  extend T::Sig

  sidekiq_options queue: :default, retry: 3

  STALE_AFTER = T.let(7.days, ActiveSupport::Duration)

  sig { void }
  def perform
    UserInventory.where("updated_at < ?", STALE_AFTER.ago).pluck(:steam_id).each do |steam_id|
      UserInventorySyncWorker.perform_async(steam_id)
    end
  end
end
