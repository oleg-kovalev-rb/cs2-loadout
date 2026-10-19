# typed: strict

class ItemPriceDynamicsSerializer
  extend T::Sig

  class << self
    extend T::Sig

    sig do
      params(
        priced_items: T::Hash[String, Item],
        pending_count: Integer
      ).returns(T::Hash[Symbol, T.untyped])
    end
    def call(priced_items, pending_count)
      {
        prices: prices_json(priced_items),
        pending_count: pending_count
      }
    end

    private

    sig { params(priced_items: T::Hash[String, Item]).returns(T::Hash[String, T::Hash[Symbol, T.untyped]]) }
    def prices_json(priced_items)
      prices = T.let({}, T::Hash[String, T::Hash[Symbol, T.untyped]])

      priced_items.each do |name, item|
        current_price_cents = item.current_price_cents
        next if current_price_cents.nil?

        change = item.change_24h_cents || 0
        base = current_price_cents - change

        prices[name] = {
          current_price_cents: current_price_cents,
          change_24h_cents: change,
          change_24h_percent: base.zero? ? 0.0 : (change.to_f / base * 100).round(2),
          price_updated_at: item.price_updated_at&.iso8601
        }
      end

      prices
    end
  end
end
