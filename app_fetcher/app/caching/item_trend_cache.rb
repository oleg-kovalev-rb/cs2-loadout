# typed: strict

class ItemTrendCache
  extend T::Sig

  TrendPoint = T.type_alias { { at: String, price_cents: Integer, volume: Integer } }

  CACHE_KEY_VERSION = T.let(1, Integer)
  SAFETY_NET_TTL = T.let(15.minutes, ActiveSupport::Duration)
  TREND_WINDOW = T.let(7.days, ActiveSupport::Duration)
  TREND_POINTS = T.let(5, Integer)

  class << self
    extend T::Sig

    sig { params(market_hash_names: T::Array[String]).returns(T::Hash[String, T::Array[TrendPoint]]) }
    def fetch_for(market_hash_names)
      keys_by_name = market_hash_names.index_by { |name| cache_key(name) }
      cached = Rails.cache.read_multi(*keys_by_name.keys)

      missing_names = keys_by_name.reject { |key, _name| cached.key?(key) }.values

      if missing_names.any?
        items_by_name = Item.where(market_hash_name: missing_names).index_by(&:market_hash_name)

        logs_by_item_id = PriceLog.where(item_id: items_by_name.values.map(&:id), created_at: TREND_WINDOW.ago..)
                                   .order(:created_at)
                                   .group_by(&:item_id)

        to_write = T.let({}, T::Hash[T::Array[T.any(String, Integer)], T::Array[TrendPoint]])
        missing_names.each do |name|
          item = items_by_name[name]
          next unless item

          to_write[cache_key(name)] = downsample(logs_by_item_id[item.id] || [])
        end

        Rails.cache.write_multi(to_write, expires_in: SAFETY_NET_TTL) if to_write.any?
        cached.merge!(to_write)
      end

      keys_by_name.each_with_object({}) do |(key, name), result|
        points = cached[key]
        result[name] = points if points.present?
      end
    end

    sig { params(market_hash_name: String).void }
    def invalidate(market_hash_name)
      Rails.cache.delete(cache_key(market_hash_name))
    end

    private

    sig { params(market_hash_name: String).returns(T::Array[T.any(String, Integer)]) }
    def cache_key(market_hash_name)
      [ "item_trend", CACHE_KEY_VERSION, market_hash_name ]
    end

    # Cursor-based downsampling: walks TREND_POINTS evenly-spaced target
    # timestamps across the window, advancing a single forward-only index
    # into the already-sorted logs, carrying the last-seen log forward but
    # only emitting a point when it's a genuinely new log (no duplicate
    # carry-forward entries, so a sparsely-logged item returns fewer than
    # TREND_POINTS points instead of padding).
    sig { params(logs: T::Array[PriceLog]).returns(T::Array[TrendPoint]) }
    def downsample(logs)
      return [] if logs.empty?

      start = TREND_WINDOW.ago
      window_seconds = TREND_WINDOW.to_i
      cursor = T.let(0, Integer)
      latest = T.let(nil, T.nilable(PriceLog))
      last_emitted_id = T.let(nil, T.nilable(Integer))
      points = T.let([], T::Array[TrendPoint])

      TREND_POINTS.times do |i|
        target = start + (window_seconds * i / (TREND_POINTS - 1)).seconds

        while cursor < logs.size && logs.fetch(cursor).created_at <= target
          latest = logs.fetch(cursor)
          cursor += 1
        end

        next if latest.nil? || latest.id == last_emitted_id

        points << { at: latest.created_at.iso8601, price_cents: latest.lowest_price_cents, volume: latest.volume }
        last_emitted_id = latest.id
      end

      points
    end
  end
end
