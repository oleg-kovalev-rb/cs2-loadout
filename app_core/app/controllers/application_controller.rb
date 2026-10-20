# typed: strict

class ApplicationController < ActionController::Base
  extend T::Sig

  # Only allow modern browsers supporting webp images, web push, badges, import maps, CSS nesting, and CSS :has.
  allow_browser versions: :modern

  # Changes to the importmap will invalidate the etag for HTML responses
  stale_when_importmap_changes

  before_action :prevent_demo_caching

  private

  sig { void }
  def prevent_demo_caching
    return unless current_demo

    response.headers["Cache-Control"] = "private, no-store"
  end

  sig { returns(T.nilable(User)) }
  def current_user
    @current_user ||= T.let(User.find_by(id: session[:user_id]), T.nilable(User))
  end
  helper_method :current_user

  sig { returns(T.nilable(Demo::SessionStore::Session)) }
  def current_demo
    return @current_demo if defined?(@current_demo)

    id = cookies.encrypted[:demo_id]
    @current_demo = T.let(
      id.is_a?(String) ? Demo::SessionStore.find(id) : nil,
      T.nilable(Demo::SessionStore::Session)
    )

    cookies.delete(:demo_id) if id.is_a?(String) && @current_demo.nil?
    @current_demo
  rescue Redis::BaseError => e
    Rails.logger.warn("[Demo] Redis unavailable: #{e.message}")
    @current_demo = T.let(nil, T.nilable(Demo::SessionStore::Session))
  end
  helper_method :current_demo

  sig { returns(T.nilable(String)) }
  def demo_bridge_token
    return @demo_bridge_token if defined?(@demo_bridge_token)

    demo = current_demo
    @demo_bridge_token = T.let(demo ? Demo::BridgeToken.encode(demo) : nil, T.nilable(String))
  end
  helper_method :demo_bridge_token
end
