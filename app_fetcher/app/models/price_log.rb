# typed: strict

class PriceLog < ApplicationRecord
  extend T::Sig

  SUPPORTED_PERIODS = T.let(PricePeriod.values.freeze, T::Array[PricePeriod])

  scope :for_period, ->(period) {
    cutoff = period.since
    cutoff ? where(created_at: cutoff..) : all
  }

  belongs_to :item

  validates :lowest_price_cents, :median_price_cents, :volume, presence: true
end
