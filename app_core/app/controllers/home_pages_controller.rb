class HomePagesController < ApplicationController
  def index
    if current_user
      redirect_to dashboard_path
      return
    end

    @user_name = params[:user_name]

    render :index
  end
end
