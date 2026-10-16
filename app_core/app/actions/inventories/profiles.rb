# typed: strict

module Inventories
  # Batch lookup of app_core-owned Steam profile fields (nickname/avatar)
  # for a set of steam_ids — the "app_core-owned enrichment" endpoint's
  # one collaborator. See agent/styleguides/core/architecture-layers.md's
  # "App_core-Owned Enrichment (Public Pages)" section: it reads User
  # records as data, never as a caller identity.
  class Profiles
    extend T::Sig

    MAX_STEAM_IDS = T.let(100, Integer)

    class << self
      extend T::Sig

      sig do
        params(steam_ids: T::Array[T.nilable(String)])
          .returns(T::Hash[String, T::Hash[Symbol, T.nilable(String)]])
      end
      def call(steam_ids)
        ids = steam_ids.map(&:to_s).reject(&:empty?).uniq.first(MAX_STEAM_IDS)
        return {} if ids.empty?

        profiles = T.let({}, T::Hash[String, T::Hash[Symbol, T.nilable(String)]])
        User.where(steam_id: ids).pluck(:steam_id, :nickname, :avatar_url).each do |steam_id, nickname, avatar_url|
          profiles[steam_id] = { nickname: nickname, avatar_url: avatar_url }
        end

        profiles
      end
    end
  end
end
