# typed: strict

class PriceUpdateService
  extend T::Sig

  class << self
    extend T::Sig

    sig { params(item: Item, price_data: Steam::Response::Data::ItemPriceData).returns(ServiceResult[Item]) }
    def call(item, price_data)
      price_log = PriceLogBuilder.build(item.id, price_data)

      baseline = item.price_logs
                     .where("created_at <= ?", 24.hours.ago)
                     .order(created_at: :desc)
                     .first
      baseline ||= item.price_logs.order(created_at: :asc).first

      change_24h_cents = baseline.nil? ? 0 : (price_log.lowest_price_cents - baseline.lowest_price_cents).to_i

      Item.transaction do
        price_log.save!
        item.update!(
          current_price_cents: price_log.lowest_price_cents,
          change_24h_cents: change_24h_cents,
          price_unavailable: false,
          price_updated_at: Time.current
        )
      end

      ServiceResult[Item].new(status: ServiceResult::Status::Ok, data: item, error: nil)
    end
  end
end
