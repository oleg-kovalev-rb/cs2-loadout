class HomePagesController < ApplicationController
  def index
    @user_name = params[:user_name]

    render :index
  end
end
