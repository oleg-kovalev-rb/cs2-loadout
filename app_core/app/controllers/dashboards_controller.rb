# typed: true

class DashboardsController < ApplicationController
  before_action :require_login, only: :show

  def show
    @bridge_token = Steam::BridgeToken.encode(current_user.steam_id)
  end

  private

  def require_login
    redirect_to root_path, alert: "Sign in to view your dashboard." unless current_user
  end
end
