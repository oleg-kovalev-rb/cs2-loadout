# typed: strict

module Admin
  class BaseController < ApplicationController
    extend T::Sig

    before_action :require_admin!

    private

    sig { returns(T.nilable(AdminUser)) }
    def current_admin_user
      @current_admin_user ||= T.let(AdminUser.find_by(id: session[:admin_user_id]), T.nilable(AdminUser))
    end
    helper_method :current_admin_user

    sig { void }
    def require_admin!
      return if current_admin_user

      render json: { message: "Unauthorized" }, status: :unauthorized
    end
  end
end
