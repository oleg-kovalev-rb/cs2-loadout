# app/controllers/sessions_controller.rb
# typed: true

class SessionsController < ApplicationController
  def create
    return_to = callback_session_url
    realm = root_url

    redirect_to Steam::Authenticator.auth_url(return_to, realm), allow_other_host: true
  end

  def callback
    steam_id = Steam::Authenticator.validate!(request.query_parameters.except('controller', 'action'))
    
    #user.save ?

    redirect_to root_path, notice: "Successfully logged in with Steam!"
    
  rescue Steam::AuthError => e
    Rails.logger.warn("[Auth] Failed Steam Login: #{e.message}")
    redirect_to root_path, alert: "Login failed. Please try again."
  end

  def destroy
    session.delete(:user_id)
    redirect_to root_path, notice: "Logged out."
  end
end