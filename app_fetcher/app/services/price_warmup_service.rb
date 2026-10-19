# typed: strict

class PriceWarmupService
  extend T::Sig

  WARMUP_CAP = T.let(20, Integer)
  DEDUP_TTL = T.let(90.seconds, ActiveSupport::Duration)
  DEDUP_KEY_PREFIX = T.let("price_warmup_pending", String)

  class << self
    extend T::Sig

    sig { params(items: T::Array[Item]).returns(ServiceResult[T::Array[Integer]]) }
    def call(items)
      enqueued_ids = T.let([], T::Array[Integer])

      items.select { |item| item.current_price_cents.nil? }.first(WARMUP_CAP).each do |item|
        next unless Rails.cache.write(dedup_key(item), true, unless_exist: true, expires_in: DEDUP_TTL)

        PriceUpdateWorker.perform_async(item.id)
        enqueued_ids << item.id
      end

      ServiceResult[T::Array[Integer]].new(
        status: ServiceResult::Status::Ok,
        data: enqueued_ids,
        error: nil
      )
    end

    private

    sig { params(item: Item).returns(String) }
    def dedup_key(item)
      "#{DEDUP_KEY_PREFIX}:#{item.id}"
    end
  end
end
