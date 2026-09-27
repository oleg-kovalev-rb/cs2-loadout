module SqlQueryCounterHelper
  # `model:` scopes the count to queries against one AR model (e.g. `Item`),
  # excluding the cache store's own backing queries (e.g. `SolidCache::Entry`)
  # so a test can assert "no query against this table" without being tripped
  # up by solid_cache's own reads/writes on every fetch, hit or miss.
  def count_queries(model: nil, &block)
    count = 0

    counter = ->(_name, _started, _finished, _unique_id, payload) do
      next if payload[:name] == "SCHEMA" || payload[:cached]
      next if model && !payload[:name].to_s.start_with?(model.name)

      count += 1
    end

    ActiveSupport::Notifications.subscribed(counter, "sql.active_record", &block)

    count
  end
end

RSpec.configure do |config|
  config.include SqlQueryCounterHelper
end
