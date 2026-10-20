# typed: strict

class PriceLogBuilder
  extend T::Sig

  PRICE_REGEXP = T.let(/[0-9][0-9.,\s\u00A0\u202F]*/, Regexp)
  SPACE_REGEXP = T.let(/[\s\u00A0\u202F]/, Regexp)
  SEPARATOR_REGEXP = T.let(/[.,]/, Regexp)

  sig { params(item_id: Integer, price_data: Steam::Response::Data::ItemPriceData).returns(PriceLog) }
  def self.build(item_id, price_data)
    PriceLog.new(
      item_id:,
      lowest_price_cents: to_cents(price_data.lowest_price),
      median_price_cents: to_cents(price_data.median_price),
      volume: parse_volume(price_data.volume)
    )
  end

  class << self
    extend T::Sig
    private

    sig { params(price_string: T.nilable(String)).returns(Integer) }
    def to_cents(price_string)
      return 0 if price_string.nil? || price_string.empty?

      match = price_string.match(PRICE_REGEXP)
      return 0 unless match

      raw_price = match[0]
      return 0 if raw_price.nil?

      integer_part, fraction_part = split_price(raw_price.gsub(SPACE_REGEXP, ""))

      integer_part.to_i * 100 + fraction_to_cents(fraction_part)
    end

    sig { params(digits: String).returns([ String, T.nilable(String) ]) }
    def split_price(digits)
      last_separator_index = digits.rindex(SEPARATOR_REGEXP)
      return [ digits, nil ] if last_separator_index.nil?

      separator = T.must(digits[last_separator_index])
      return [ digits.delete(".,"), nil ] unless decimal_separator?(digits, last_separator_index, separator)

      [
        T.must(digits[0...last_separator_index]).delete(".,"),
        T.must(digits[(last_separator_index + 1)..])
      ]
    end

    sig { params(digits: String, index: Integer, separator: String).returns(T::Boolean) }
    def decimal_separator?(digits, index, separator)
      return true if digits.include?(separator == "." ? "," : ".")
      return false if digits.count(separator) > 1

      digits.length - index - 1 != 3
    end

    sig { params(fraction: T.nilable(String)).returns(Integer) }
    def fraction_to_cents(fraction)
      return 0 if fraction.nil? || fraction.empty?

      (fraction[0, 3].to_s.ljust(3, "0").to_i + 5) / 10
    end

    sig { params(volume_string: T.nilable(String)).returns(Integer) }
    def parse_volume(volume_string)
      return 0 if volume_string.nil? || volume_string.empty?

      volume_string.gsub(SPACE_REGEXP, "").tr(",", "").to_i
    end
  end
end
