# typed: strict

module Admin
  class PriceLogSerializer
    extend T::Sig

    class << self
      extend T::Sig

      sig { params(meta: T::Hash[Symbol, Integer], price_logs: T::Enumerable[PriceLog]).returns(T::Hash[Symbol, T.untyped]) }
      def call_for_list(meta, price_logs)
        { meta: meta, price_logs: price_logs.map { |price_log| price_log_json(price_log) } }
      end

      private

      sig { params(price_log: PriceLog).returns(T::Hash[Symbol, T.untyped]) }
      def price_log_json(price_log)
        {
          id: price_log.id,
          item_id: price_log.item_id,
          market_hash_name: T.must(price_log.item).market_hash_name,
          lowest_price_cents: price_log.lowest_price_cents,
          median_price_cents: price_log.median_price_cents,
          volume: price_log.volume,
          created_at: price_log.created_at.iso8601
        }
      end
    end
  end
end
