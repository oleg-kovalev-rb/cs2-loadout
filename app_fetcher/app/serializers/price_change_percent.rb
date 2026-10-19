# typed: strict

class PriceChangePercent
  extend T::Sig

  class << self
    extend T::Sig

    sig { params(current_cents: T.nilable(Integer), change_cents: Integer).returns(Float) }
    def call(current_cents:, change_cents:)
      return 0.0 if current_cents.nil?

      base = current_cents - change_cents
      base.zero? ? 0.0 : (change_cents.to_f / base * 100).round(2).to_f
    end
  end
end
