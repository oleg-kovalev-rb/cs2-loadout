# typed: strict

class PriceLog < ApplicationRecord
  belongs_to :item

  validates :lowest_price_cents, :median_price_cents, :volume, presence: true
end
