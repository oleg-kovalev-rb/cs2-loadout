# typed: strict

class InventoryValueHistoryQuery
  extend T::Sig

  class << self
    extend T::Sig

    sig do
      params(steam_id: String, params: ActionController::Parameters)
        .returns(InventoryValueQuery::InventoryValue)
    end
    def call(steam_id, params)
      range = Options::DateRange::Param.new(
        allowed_ranges: InventoryValueQuery::SUPPORTED_RANGES,
        default: Options::DateRange::AllTime,
        error_class: Api::V1::UnsupportedParamError
      ).parse(params[:period])

      InventoryValueQuery.call(steam_id, range)
    end
  end
end
