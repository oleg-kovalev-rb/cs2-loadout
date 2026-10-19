# typed: strict

class PricePeriod < T::Enum
  extend T::Sig

  enums do
    TwentyFourHours = new("24h")
    SevenDays = new("7d")
    ThirtyDays = new("30d")
    OneYear = new("1y")
    All = new("all")
  end

  class << self
    extend T::Sig

    sig do
      params(
        raw_value: T.untyped,
        supported: T::Array[PricePeriod],
        default: PricePeriod
      ).returns(T.nilable(PricePeriod))
    end
    def resolve(raw_value, supported:, default:)
      period = try_deserialize(raw_value.presence || default.serialize)
      return nil unless period

      supported.include?(period) ? period : nil
    end
  end

  sig { returns(T.nilable(ActiveSupport::Duration)) }
  def duration
    case self
    when TwentyFourHours then 24.hours
    when SevenDays then 7.days
    when ThirtyDays then 30.days
    when OneYear then 365.days
    when All then nil
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
