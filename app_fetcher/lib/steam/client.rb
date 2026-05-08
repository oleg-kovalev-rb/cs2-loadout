# typed: strict

require 'faraday'
require 'prop'

module Steam
  class Client
    class RateLimitError < StandardError; end

    extend T::Sig

    BASE_URL = T.let("https://steamcommunity.com".freeze, String)

    CS2_APPID = T.let(730, Integer)

    sig { void }
    def initialize
      @connection = T.let(Faraday.new(url: BASE_URL) do |f|
        f.headers = default_headers

        f.request :user_agent_rotator
        f.request :url_encoded
        f.adapter Faraday.default_adapter

        f.options.timeout = 10
        f.options.open_timeout = 5
      end, Faraday::Connection)
    end

    sig { params(market_hash_name: String).returns(Steam::Response[ItemPriceData]) }
    def fetch_item_price(market_hash_name)
      response = perform_request(Steam::ItemPriceData, "/market/priceoverview/", :steam_price) do
        { market_hash_name: market_hash_name, appid: CS2_APPID, currency: 1 }
      end

      T.cast(response, Steam::Response[Steam::ItemPriceData])
    end

    sig { params(steam_id: String).returns(Steam::Response[InventoryData]) }
    def fetch_user_inventory(steam_id)
      response = perform_request(Steam::InventoryData, "/inventory/#{steam_id}/#{CS2_APPID}/2", :steam_inventory) do
        { l: "english", count: 2000 }
      end

      T.cast(response, Steam::Response[Steam::InventoryData])
    end

    private

    sig do
      params(
        dto_class: T.untyped, 
        path: String,
        limit_key: Symbol,
        params_blk: T.proc.returns(T::Hash[Symbol, T.untyped])
      ).returns(T.untyped) 
    end
    def perform_request(dto_class, path, limit_key, &params_blk)
      Prop.throttle!("#{limit_key}_rpm".to_sym, "global")
      Prop.throttle!("#{limit_key}_rpd".to_sym, "global")

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
