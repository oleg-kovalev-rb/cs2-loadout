# typed: strict

require 'net/http'
require 'uri'
require 'json'

module Steam
  class ProfileFetcher
    extend T::Sig

    ProfileData = T.type_alias { { nickname: String, avatar_url: String } }

    sig { params(steam_id: String).returns(T.nilable(ProfileData)) }
    def self.call(steam_id)
      api_key = ENV.fetch("STEAM_WEB_API_KEY")

      return nil if api_key.empty?

      uri = URI("https://api.steampowered.com/ISteamUser/GetPlayerSummaries/v0002/")
      uri.query = URI.encode_www_form({
        key: api_key,
        steamids: steam_id
      })

      response = Net::HTTP.get_response(uri)
      return nil unless response.is_a?(Net::HTTPSuccess)

      data = JSON.parse(response.body)
      player = data.dig("response", "players", 0)

      return nil unless player

      {
        nickname: player["personaname"].to_s,
        avatar_url: player["avatarfull"].to_s
      }
    rescue JSON::ParserError, Net::OpenTimeout, Net::ReadTimeout
      nil
    end
  end
end
