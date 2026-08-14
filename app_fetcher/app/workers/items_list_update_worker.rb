# typed: strict

class ItemsListUpdateWorker
  include Sidekiq::Worker
  extend T::Sig

  sidekiq_options queue: :default, retry: 3

  sig { params(names: T::Array[String]).void }
  def perform(names)
    items_attrs = Steam::ItemParser.parse_collection(names)

    Item.upsert_all(
      items_attrs, 
      unique_by: :market_hash_name
    )
  end
end
