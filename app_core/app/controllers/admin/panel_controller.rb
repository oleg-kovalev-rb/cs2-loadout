# typed: strict

module Admin
  class PanelController < BaseController
    extend T::Sig

    sig { void }
    def show
      @bridge_token = T.let(
        Admin::BridgeToken.encode(T.must(current_admin_user).id.to_s),
        T.nilable(String)
      )
    end
  end
end
