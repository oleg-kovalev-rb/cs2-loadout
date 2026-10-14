# typed: strict

module Admin
  class SessionsController < ApplicationController
    extend T::Sig

    sig { void }
    def new; end

    sig { void }
    def create
      admin_user = AdminUser.find_by(email: AdminUser.normalize_value_for(:email, params[:email]))

      if admin_user&.authenticate(params[:password])
        session[:admin_user_id] = admin_user.id
        respond_to do |format|
          format.json { render json: { message: "Signed in" }, status: :ok }
          format.html { redirect_to admin_panel_path }
        end
      else
        respond_to do |format|
          format.json { render json: { message: "Invalid email or password" }, status: :unauthorized }
          format.html do
            @error = T.let("Invalid email or password", T.nilable(String))
            render :new, status: :unprocessable_content
          end
        end
      end
    end

    sig { void }
    def destroy
      session.delete(:admin_user_id)
      respond_to do |format|
        format.json { render json: { message: "Signed out" }, status: :ok }
        format.html { redirect_to new_admin_session_path }
      end
    end
  end
end
