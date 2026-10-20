# typed: strict

class ApplicationController < ActionController::Base
  extend T::Sig

  # Only allow modern browsers supporting webp images, web push, badges, import maps, CSS nesting, and CSS :has.
  allow_browser versions: :modern

  # Changes to the importmap will invalidate the etag for HTML responses
  stale_when_importmap_changes

  private

  sig { returns(T.nilable(User)) }
  def current_user
    @current_user ||= T.let(User.find_by(id: session[:user_id]), T.nilable(User))
  end
  helper_method :current_user
end
