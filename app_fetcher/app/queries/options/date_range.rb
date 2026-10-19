# typed: strict

module Options
  class DateRange < T::Enum
    extend T::Sig

    enums do
      Last24Hours = new("24h")
      Last7Days = new("7d")
      Last30Days = new("30d")
      LastYear = new("1y")
      AllTime = new("all")
    end

    class Param
      extend T::Sig

      sig do
        params(
          allowed_ranges: T::Array[Options::DateRange],
          default: Options::DateRange,
          error_class: T.class_of(StandardError)
        ).void
      end
      def initialize(allowed_ranges:, default:, error_class:)
        @allowed_ranges = T.let(allowed_ranges, T::Array[Options::DateRange])
        @default = T.let(default, Options::DateRange)
        @error_class = T.let(error_class, T.class_of(StandardError))
      end

      sig { params(raw: T.untyped).returns(Options::DateRange) }
      def parse(raw)
        range = Options::DateRange.try_deserialize(raw.presence || @default.serialize)

        return range if range && @allowed_ranges.include?(range)

        raise @error_class, "Unsupported period: #{raw}"
      end
    end

    sig { returns(T.nilable(ActiveSupport::Duration)) }
    def duration
      case self
      when Last24Hours then 24.hours
      when Last7Days then 7.days
      when Last30Days then 30.days
      when LastYear then 365.days
      when AllTime then nil
      else T.absurd(self)
      end
    end

    sig { returns(T.nilable(ActiveSupport::TimeWithZone)) }
    def since
      duration&.ago
    end

    sig { returns(T.nilable(Date)) }
    def since_date
      since&.to_date
    end
  end
end
