# typed: strict

module Admin
  class InventoryValueLogSerializer
    extend T::Sig

    class << self
      extend T::Sig

      sig { params(meta: T::Hash[Symbol, Integer], logs: T::Enumerable[InventoryValueLog]).returns(T::Hash[Symbol, T.untyped]) }
      def call_for_list(meta, logs)
        { meta: meta, inventory_value_logs: logs.map { |log| log_json(log) } }
      end

      private

      sig { params(log: InventoryValueLog).returns(T::Hash[Symbol, T.untyped]) }
      def log_json(log)
        {
          id: log.id,
          steam_id: log.steam_id,
          log_date: log.log_date.iso8601,
          total_value_cents: log.total_value_cents
        }
      end
    end
  end
end
