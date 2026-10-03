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
end
