# typed: strict

class DashboardsController < ApplicationController
  extend T::Sig

  sig { void }
  def show
    @bridge_token = T.let(
      current_user ? Steam::BridgeToken.encode(current_user.steam_id) : nil,
      T.nilable(String)
    )
  end
end
