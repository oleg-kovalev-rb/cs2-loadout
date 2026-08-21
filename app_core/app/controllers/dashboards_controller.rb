# typed: true

class DashboardsController < ApplicationController
  before_action :require_login, only: :show

  def show
    respond_to do |format|
      format.html
      format.json { render json: Dashboard::BuildSnapshot.call(current_user) }
    end
  end

  private

  def require_login
    redirect_to root_path, alert: "Sign in to view your dashboard." unless current_user
  end
end
