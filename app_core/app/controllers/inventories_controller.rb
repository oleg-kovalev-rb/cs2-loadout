# typed: strict

class InventoriesController < ApplicationController
  extend T::Sig

  sig { void }
  def index; end

  sig { void }
  def show
    @profile = T.let(User.find_by(steam_id: params[:steam_id]), T.nilable(User))
  end

  sig { void }
  def profiles
    render json: { profiles: Inventories::Profiles.call(steam_ids_param) }
  end

  private

  sig { returns(T::Array[T.nilable(String)]) }
  def steam_ids_param
    Array(params[:steam_ids])
  end
end
