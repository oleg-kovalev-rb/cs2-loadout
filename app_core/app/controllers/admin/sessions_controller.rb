# typed: strict

module Admin
  class SessionsController < ApplicationController
    extend T::Sig

    sig { void }
    def create
      admin_user = AdminUser.find_by(email: AdminUser.normalize_value_for(:email, params[:email]))

      if admin_user&.authenticate(params[:password])
        session[:admin_user_id] = admin_user.id
        render json: { message: "Signed in" }, status: :ok
      else
        render json: { message: "Invalid email or password" }, status: :unauthorized
      end
    end

    sig { void }
    def destroy
      session.delete(:admin_user_id)
      render json: { message: "Signed out" }, status: :ok
    end
  end
end
