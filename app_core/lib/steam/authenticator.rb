# typed: strict

require "net/http"
require "uri"

module Steam
  class AuthError < StandardError; end

  class Authenticator
    extend T::Sig

    STEAM_OPENID_URL = T.let("https://steamcommunity.com/openid/login".freeze, String)
    OPENID_NS = T.let("http://specs.openid.net/auth/2.0".freeze, String)
    IDENTIFIER_SELECT = T.let("http://specs.openid.net/auth/2.0/identifier_select".freeze, String)

    sig { params(return_to: String, realm: String).returns(String) }
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

    sig { params(auth_params: T::Hash[String, String]).returns(String) }
    def self.validate!(auth_params)
      raise AuthError, "Missing Steam payload" if auth_params.empty?

      check_params = auth_params.dup
      check_params["openid.mode"] = "check_authentication"

      uri = URI(STEAM_OPENID_URL)

      http = Net::HTTP.new(uri.host, uri.port)
      http.use_ssl = true

      request = Net::HTTP::Post.new(uri.path)
      request.set_form_data(check_params)

      request["User-Agent"] = "AppMain_SteamAuth_PetProject/1.0"

      response = http.request(request)
      body = response.body

      unless response.is_a?(Net::HTTPSuccess) && body&.include?("is_valid:true")
        raise AuthError, "Steam validation failed"
      end

      claimed_id = auth_params["openid.claimed_id"]
      steam_id_match = claimed_id&.match(%r{openid/id/(\d+)})

      unless steam_id_match
        raise AuthError, "Invalid SteamID format"
      end

      T.must(steam_id_match[1])
    rescue Net::OpenTimeout, Net::ReadTimeout, OpenSSL::SSL::SSLError, EOFError => e
      raise AuthError, "Network error during validation: #{e.message}"
    end
  end
end
