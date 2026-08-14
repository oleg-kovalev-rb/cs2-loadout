require "net/http"
require "uri"

module Steam
  class AuthError < StandardError; end

  class Authenticator
    STEAM_OPENID_URL = "https://steamcommunity.com/openid/login".freeze
    OPENID_NS = "http://specs.openid.net/auth/2.0".freeze
    IDENTIFIER_SELECT = "http://specs.openid.net/auth/2.0/identifier_select".freeze

    def self.auth_url(return_to, realm)
      uri = URI(STEAM_OPENID_URL)
      uri.query = URI.encode_www_form({
        "openid.ns"         => OPENID_NS,
        "openid.mode"       => "checkid_setup",
        "openid.return_to"  => return_to,
        "openid.realm"      => realm,
        "openid.identity"   => IDENTIFIER_SELECT,
        "openid.claimed_id" => IDENTIFIER_SELECT
      })

      uri.to_s
    end

    def self.validate!(auth_params)
      raise AuthError, "Missing Steam payload" if auth_params.empty?

      check_params = auth_params.dup
      check_params['openid.mode'] = 'check_authentication'

      uri = URI(STEAM_OPENID_URL)
      
      # 1. Настраиваем HTTP клиента явно
      http = Net::HTTP.new(uri.host, uri.port)
      http.use_ssl = true

      # 2. Формируем POST запрос
      request = Net::HTTP::Post.new(uri.request_uri)
      request.set_form_data(check_params)
      
      # 3. ДОБАВЛЯЕМ USER-AGENT (Критично для Steam API!)
      request['User-Agent'] = 'AppMain_SteamAuth_PetProject/1.0'

      # 4. Выполняем запрос
      response = http.request(request)

      unless response.is_a?(Net::HTTPSuccess) && response.body.include?("is_valid:true")
        raise AuthError, "Steam validation failed"
      end

      claimed_id = auth_params['openid.claimed_id']
      steam_id_match = claimed_id&.match(%r{openid/id/(\d+)})

      unless steam_id_match
        raise AuthError, "Invalid SteamID format"
      end

      steam_id_match[1]
    rescue Net::OpenTimeout, Net::ReadTimeout, OpenSSL::SSL::SSLError, EOFError => e
      # Перехватываем сетевые и SSL ошибки, чтобы не ронять приложение (500 Error),
      # а корректно отработать через наш кастомный AuthError
      raise AuthError, "Network error during validation: #{e.message}"
    end
  end
end