# typed: strict

require "json"
require "securerandom"

module Demo
  class SessionStore
    extend T::Sig

    class Session < T::Struct
      const :id, String
      const :seed, Integer
      const :created_at, Time
    end

    TTL_SECONDS = T.let(12.hours.to_i, Integer)
    KEY_PREFIX = T.let("demo:session:", String)

    class << self
      extend T::Sig

      sig { returns(Session) }
      def create
        session = Session.new(
          id: SecureRandom.uuid,
          seed: SecureRandom.random_number(2**31).to_i,
          created_at: Time.current.to_time
        )

        DEMO_REDIS_POOL.with do |redis|
          redis.set(key(session.id), serialize(session), ex: TTL_SECONDS)
        end

        session
      end

      sig { params(id: String).returns(T.nilable(Session)) }
      def find(id)
        raw = DEMO_REDIS_POOL.with { |redis| redis.get(key(id)) }
        return nil if raw.nil?

        deserialize(id, raw)
      end

      sig { params(id: String).returns(T.nilable(Integer)) }
      def remaining_seconds(id)
        ttl = DEMO_REDIS_POOL.with { |redis| redis.ttl(key(id)) }
        ttl.positive? ? ttl : nil
      end

      sig { params(id: String).void }
      def delete(id)
        DEMO_REDIS_POOL.with { |redis| redis.del(key(id)) }
      end

      private

      sig { params(id: String).returns(String) }
      def key(id)
        "#{KEY_PREFIX}#{id}"
      end

      sig { params(session: Session).returns(String) }
      def serialize(session)
        JSON.generate(
          id: session.id,
          seed: session.seed,
          created_at: session.created_at.iso8601
        )
      end

      sig { params(id: String, raw: String).returns(Session) }
      def deserialize(id, raw)
        data = T.let(JSON.parse(raw), T::Hash[String, T.untyped])

        Session.new(
          id: id,
          seed: Integer(data.fetch("seed")),
          created_at: Time.iso8601(data.fetch("created_at"))
        )
      end
    end
  end
end
