# typed: strict

class DashboardsController < ApplicationController
  extend T::Sig

  sig { void }
  def show
    user = current_user
    @bridge_token = T.let(
      user ? Steam::BridgeToken.encode(user.steam_id) : nil,
      T.nilable(String)
    )
  end
end
