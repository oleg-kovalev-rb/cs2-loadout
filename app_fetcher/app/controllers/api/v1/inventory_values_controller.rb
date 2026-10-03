# typed: strict

module Api
  module V1
    class InventoryValuesController < ApplicationController
      extend T::Sig

      ALLOWED_PERIODS = T.let(
        [ PricePeriod::SevenDays, PricePeriod::ThirtyDays, PricePeriod::OneYear, PricePeriod::All ].freeze,
        T::Array[PricePeriod]
      )

      sig { void }
      def index
        period = PricePeriod.try_deserialize(params[:period].presence || "all")

        unless period && ALLOWED_PERIODS.include?(period)
          render json: { message: "Unsupported period: #{params[:period]}" }, status: :bad_request
          return
        end

        logs = InventoryValueLog.where(steam_id: current_steam_id).order(:log_date)

        if logs.empty?
          InventoryValueRecordingService.new(current_steam_id).call!
          logs = InventoryValueLog.where(steam_id: current_steam_id).order(:log_date)
        end

        since = period.duration&.ago&.to_date
        logs_in_period = since ? logs.select { |log| log.log_date >= since } : logs

        render json: logs_in_period.map { |log| { date: log.log_date.iso8601, total_value_cents: log.total_value_cents } }, status: :ok
      end
    end
  end
end
