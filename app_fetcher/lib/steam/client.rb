# typed: strict

require 'faraday'
require 'prop'

module Steam
  class Client
    class RateLimitError < StandardError; end

    extend T::Sig

    BASE_URL = T.let("https://steamcommunity.com".freeze, String)

    CS2_APPID = T.let(730, Integer)

    LIMIT_MAP = T.let({
      price_overview: :steam_price_api,
      price_history:  :steam_history_api,
      assets:         :steam_assets_api
    }.freeze, T::Hash[Symbol, Symbol])

    sig { void }
    def initialize
      @connection = T.let(Faraday.new(url: BASE_URL) do |f|
        f.headers = default_headers
        f.request :url_encoded
        f.adapter Faraday.default_adapter
        f.options.timeout = 10
        f.options.open_timeout = 5
      end, Faraday::Connection)
    end

    sig { params(market_hash_name: String).returns(Steam::Response[ItemPriceData]) }
    def fetch_item_price(market_hash_name)
      response = perform_request(Steam::ItemPriceData, "/market/priceoverview/") do
        { market_hash_name: market_hash_name, appid: CS2_APPID, currency: 1 }
      end

      T.cast(response, Steam::Response[Steam::ItemPriceData])
    end

    sig { params(steam_id: String).returns(Steam::Response[InventoryData]) }
    def fetch_user_inventory(steam_id)
      response = perform_request(Steam::InventoryData, "/inventory/#{steam_id}/#{CS2_APPID}/2") do
        { l: "english", count: 2000 }
      end

      T.cast(response, Steam::Response[Steam::InventoryData])
    end

    private

    sig { returns(T::Hash[String, String]) }
    def default_headers
      {
        "User-Agent" => "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36",
        "Accept" => "application/json, text/javascript, */*; q=0.01",
        "Accept-Language" => "ru-RU,ru;q=0.9,en-US;q=0.8,en;q=0.7",
        "Referer" => "https://steamcommunity.com/market/",
        "X-Requested-With" => "XMLHttpRequest",
        "Connection" => "keep-alive"
      }
    end

    sig do 
      params(
        dto_class: T.untyped, 
        path: String,
        params_blk: T.proc.returns(T::Hash[Symbol, T.untyped])
      ).returns(T.untyped) 
    end
    def perform_request(dto_class, path, &params_blk)
      response = @connection.get(path, params_blk.call)

      case response.status
      when 200
        body = JSON.parse(response.body)
        return Steam::Response[T.untyped].new(status: 404, error: "Not Found") unless body['success']

        data = dto_class.from_hash(body)
        Steam::Response[T.untyped].new(status: 200, data: data)
      when 429
        Steam::Response[T.untyped].new(status: 429, error: "Rate Limit Exceeded")
      else
        Steam::Response[T.untyped].new(status: response.status, error: "Steam API Error")
      end
    rescue Faraday::Error, JSON::ParserError => e
      Steam::Response[T.untyped].new(status: 500, error: e.message)
    end
  end
end
