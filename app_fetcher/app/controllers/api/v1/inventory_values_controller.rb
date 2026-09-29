# typed: strict

module Api
  module V1
    class InventoryValuesController < ApplicationController
      extend T::Sig

      SEED_DEDUP_TTL = T.let(90.seconds, ActiveSupport::Duration)

      sig { void }
      def index
        logs = InventoryValueLog.where(steam_id: current_steam_id).order(:log_date)

        enqueue_first_value_seed if logs.empty?

        render json: {
          points: logs.map { |log| { log_date: log.log_date.iso8601, total_value_cents: log.total_value_cents } }
        }, status: :ok
      end

      private

      sig { void }
      def enqueue_first_value_seed
        dedup_key = "inventory_value_seed_pending:#{current_steam_id}"
        return unless Rails.cache.write(dedup_key, true, unless_exist: true, expires_in: SEED_DEDUP_TTL)

        InventoryValueUpdateWorker.perform_async(current_steam_id)
      end
    end
  end
end
