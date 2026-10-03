# typed: strict

class PriceUpdateService
  extend T::Sig

  class << self
    extend T::Sig

    sig { params(item: Item, price_data: Steam::Response::Data::ItemPriceData).void }
    def call(item, price_data)
      price_log = PriceLogBuilder.build(item.id, price_data)

      price_24h_ago = item.price_logs
                          .where("created_at <= ?", 24.hours.ago)
                          .order(created_at: :desc)
                          .first

      change_24h_cents = price_24h_ago.nil? ? 0 : (price_log.lowest_price_cents - price_24h_ago.lowest_price_cents).to_i

      Item.transaction do
        price_log.save!
        item.update!(current_price_cents: price_log.lowest_price_cents, change_24h_cents: change_24h_cents)
      end
    end
  end
end
