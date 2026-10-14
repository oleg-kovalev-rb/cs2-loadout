# typed: strict

module Admin
  class UserInventorySerializer
    extend T::Sig

    class << self
      extend T::Sig

      sig do
        params(
          meta: T::Hash[Symbol, Integer],
          user_inventories: T::Enumerable[UserInventory],
          latest_values: T::Hash[String, T.nilable(Integer)],
          items_counts: T::Hash[Integer, Integer]
        ).returns(T::Hash[Symbol, T.untyped])
      end
      def call_for_list(meta, user_inventories, latest_values:, items_counts:)
        {
          meta: meta,
          user_inventories: user_inventories.map do |user_inventory|
            user_inventory_json(
              user_inventory, latest_values[user_inventory.steam_id], items_counts.fetch(user_inventory.id, 0)
            )
          end
        }
      end

      sig do
        params(
          user_inventory: UserInventory,
          total_value_cents: T.nilable(Integer),
          items_count: Integer,
          items: T::Enumerable[UserInventoryItem]
        ).returns(T::Hash[Symbol, T.untyped])
      end
      def call(user_inventory, total_value_cents, items_count, items)
        {
          user_inventory: user_inventory_json(user_inventory, total_value_cents, items_count)
            .merge(items: inventory_items_json(items))
        }
      end

      private

      sig do
        params(user_inventory: UserInventory, total_value_cents: T.nilable(Integer), items_count: Integer)
          .returns(T::Hash[Symbol, T.untyped])
      end
      def user_inventory_json(user_inventory, total_value_cents, items_count)
        {
          steam_id: user_inventory.steam_id,
          items_count: items_count,
          total_value_cents: total_value_cents,
          created_at: user_inventory.created_at.iso8601,
          updated_at: user_inventory.updated_at.iso8601
        }
      end

      sig { params(items: T::Enumerable[UserInventoryItem]).returns(T::Array[T::Hash[Symbol, T.untyped]]) }
      def inventory_items_json(items)
        items.map do |user_inventory_item|
          {
            market_hash_name: T.must(user_inventory_item.item).market_hash_name,
            added_at: user_inventory_item.created_at.iso8601
          }
        end
      end
    end
  end
end
