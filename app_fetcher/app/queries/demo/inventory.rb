# typed: strict

module Demo
  class Inventory
    extend T::Sig

    PATH = T.let(Rails.root.join("config/demo_inventory.yml").to_s, String)

    class Entry < T::Struct
      const :market_hash_name, String
      const :base_price_cents, Integer
    end

    class << self
      extend T::Sig

      sig { returns(T::Array[Entry]) }
      def entries
        data = YAML.safe_load_file(PATH, aliases: false) || []
        T.cast(data, T::Array[T::Hash[String, T.untyped]]).map do |entry|
          Entry.new(
            market_hash_name: entry.fetch("market_hash_name"),
            base_price_cents: Integer(entry.fetch("base_price_cents"))
          )
        end
      end

      sig { returns(T::Array[String]) }
      def market_hash_names
        entries.map(&:market_hash_name)
      end
    end
  end
end
