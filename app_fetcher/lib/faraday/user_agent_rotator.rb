# typed: strict

require 'faraday'

module Faraday
  class UserAgentRotator < Middleware
    extend T::Sig

    USER_AGENTS = T.let([
      "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/122.0.0.0 Safari/537.36",
      "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/17.3 Safari/605.1.15",
      "Mozilla/5.0 (Windows NT 10.0; Win64; x64; rv:123.0) Gecko/20100101 Firefox/123.0",
      "Mozilla/5.0 (X11; Linux x86_64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/122.0.0.0 Safari/537.36"
    ].freeze, T::Array[String])

    sig { params(app: T.untyped).void }
    def initialize(app)
      super(app)
    end

    sig { params(env: Faraday::Env).returns(Faraday::Response) }
    def call(env)
      env[:request_headers]["User-Agent"] = USER_AGENTS.sample
      @app.call(env)
    end
  end
end

Faraday::Request.register_middleware user_agent_rotator: Faraday::UserAgentRotator
