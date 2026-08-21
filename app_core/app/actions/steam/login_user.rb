# typed: strict

module Steam
  class LoginUser
    extend T::Sig

    sig { params(auth_params: T::Hash[String, String]).returns(User) }
    def self.call(auth_params)
      steam_id = Steam::Authenticator.validate!(auth_params)

      profile = Steam::ProfileFetcher.call(steam_id)

      user = User.find_or_initialize_by(steam_id: steam_id)

      if profile
        user.nickname = profile[:nickname]
        user.avatar_url = profile[:avatar_url]
      end

      user.save! unless user.persisted?

      user
    end
  end
end
