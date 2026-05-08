# typed: strict

module Steam
  class PriceLogBuilder
    extend T::Sig

    PRICE_REGEXP = T.let(/(\d+(?:[.,]\d+)?)/, Regexp)

    sig { params(item_id: Integer, price_data: Steam::ItemPriceData).returns(PriceLog) }
    def self.build(item, price_data)
      PriceLog.new(
        item_id:,
        lowest_price_cents: to_cents(price_data.lowest_price),
        median_price_cents: to_cents(price_data.median_price),
        volume: parse_volume(price_data.volume)
      )
    end

    class << self
      private

      sig { params(price_string: T.nilable(String)).returns(Integer) }
      def to_cents(price_string)
        return 0 if price_string.nil? || price_string.empty?

        match = price_string.match(PRICE_REGEXP)
        return 0 unless match && (raw_price = match[0])

        (raw_price.tr(",", ".").to_f * 100).round
      end

      sig { params(volume_string: T.nilable(String)).returns(Integer) }
      def parse_volume(volume_string)
        return 0 if volume_string.nil? || volume_string.empty?

        volume_string.tr(",", "").to_i
      end
    end
  end
end