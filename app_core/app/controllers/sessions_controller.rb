# typed: true

class SessionsController < ApplicationController
  # TODO: Add rescue from

  def create
    redirect_to Steam::Authenticator.auth_url(callback_sessions_url, root_url), allow_other_host: true
  end

  def callback
    user = Steam::LoginUser.call(request.query_parameters.except('controller', 'action'))

    session[:user_id] = user.id

    redirect_to root_path, notice: "Welcome, #{user.nickname || 'Player'}!"
  rescue Steam::AuthError => e
    Rails.logger.warn("[Auth] Failed Steam Login: #{e.message}")
    redirect_to root_path, alert: "Login failed. Please try again."
  rescue ActiveRecord::RecordInvalid => e
    Rails.logger.error("[Auth] User save failed: #{e.message}")
    redirect_to root_path, alert: "Internal server error during login."
  end

  def destroy
    session.delete(:user_id)
    redirect_to root_path, notice: "Logged out."
  end
end
