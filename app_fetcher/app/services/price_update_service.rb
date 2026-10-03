# typed: strict

class PriceUpdateService
  extend T::Sig

  class Result < T::Struct
    const :success, T::Boolean
    const :price_log, PriceLog
    const :item, Item
    const :change_24h_cents, Integer
    const :error, T.nilable(String)
  end

  class << self
    extend T::Sig

    sig { params(item: Item, price_data: Steam::Response::Data::ItemPriceData).returns(PriceUpdateService::Result) }
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

      Result.new(
        success: true,
        price_log: price_log,
        item: item,
        change_24h_cents: change_24h_cents,
        error: nil
      )
    end
  end
end
