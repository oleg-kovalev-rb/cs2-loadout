# typed: strict

require "digest"

class ItemCatalogCache
  extend T::Sig

  NormalizedFilters = T.type_alias do
    {
      page: Integer,
      per_page: Integer,
      search: T.nilable(String),
      category: T::Array[String],
      rarity: T::Array[String],
      stattrak: T::Boolean,
      sort: String
    }
  end

  CACHE_KEY_VERSION = T.let(1, Integer)
  TTL = T.let(2.minutes, ActiveSupport::Duration)

  class << self
    extend T::Sig

    sig { params(normalized_filters: NormalizedFilters).returns(T.untyped) }
    def read(normalized_filters)
      Rails.cache.read(cache_key(normalized_filters))
    end

    sig { params(normalized_filters: NormalizedFilters, value: T.untyped).void }
    def write(normalized_filters, value)
      Rails.cache.write(cache_key(normalized_filters), value, expires_in: TTL)
    end

    private

    sig { params(normalized_filters: NormalizedFilters).returns(T::Array[T.any(String, Integer)]) }
    def cache_key(normalized_filters)
      [ "items_catalog", CACHE_KEY_VERSION, Digest::SHA256.hexdigest(normalized_filters.to_json) ]
    end
  end
end
