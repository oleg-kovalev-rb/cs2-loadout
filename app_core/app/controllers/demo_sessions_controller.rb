# typed: strict

class DemoSessionsController < ApplicationController
  extend T::Sig

  sig { void }
  def create
    previous_id = cookies.encrypted[:demo_id]
    Demo::Stop.call(previous_id) if previous_id.is_a?(String)

    demo = Demo::Start.call

    cookies.encrypted[:demo_id] = {
      value: demo.id,
      expires: Demo::SessionStore::TTL_SECONDS.seconds.from_now,
      httponly: true,
      same_site: :lax,
      secure: Rails.env.production?
    }

    redirect_to root_path, notice: "Your demo is ready. It will disappear in 12 hours."
  rescue Redis::BaseError => e
    Rails.logger.error("[Demo] Could not start demo: #{e.message}")
    redirect_to root_path, alert: "Demo is temporarily unavailable."
  end

  sig { void }
  def destroy
    id = cookies.encrypted[:demo_id]
    Demo::Stop.call(id) if id.is_a?(String)
    cookies.delete(:demo_id)

    redirect_to root_path, notice: "Demo ended."
  rescue Redis::BaseError => e
    Rails.logger.warn("[Demo] Could not delete demo session: #{e.message}")
    cookies.delete(:demo_id)
    redirect_to root_path, notice: "Demo ended."
  end
end
