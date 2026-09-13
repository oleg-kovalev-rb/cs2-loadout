# Be sure to restart your server when you modify this file.

# The React dashboard in app_core calls this API directly from the browser,
# authenticated via a short-lived bridge token (see ApplicationController)
# rather than a cookie, so credentials: false is correct here.
Rails.application.config.middleware.insert_before 0, Rack::Cors do
  allow do
    origins ENV.fetch("APP_CORE_ORIGIN")

    resource "/api/v1/*",
      headers: :any,
      methods: [ :get, :post, :options ],
      credentials: false
  end
end
