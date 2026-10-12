VCR.configure do |c|
  c.cassette_library_dir = "spec/cassettes"
  c.hook_into :webmock
  c.configure_rspec_metadata!
  c.allow_http_connections_when_no_cassette = false
  c.default_cassette_options = { record: ENV["CI"] ? :none : :once }
  c.filter_sensitive_data("<STEAM_WEB_API_KEY>") { ENV["STEAM_WEB_API_KEY"] }
end
