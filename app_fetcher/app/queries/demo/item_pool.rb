# typed: strict

module Demo
  class ItemPool
    extend T::Sig

    PATH = T.let(Rails.root.join("config/demo_items.yml").to_s, String)

    class << self
      extend T::Sig

      sig { returns(T::Array[T::Hash[String, T.untyped]]) }
      def entries
        data = YAML.safe_load_file(PATH, aliases: false) || []
        T.cast(data, T::Array[T::Hash[String, T.untyped]])
      end

      sig { returns(T::Array[String]) }
      def market_hash_names
        entries.map { |entry| entry.fetch("market_hash_name") }
      end
    end
  end
end
