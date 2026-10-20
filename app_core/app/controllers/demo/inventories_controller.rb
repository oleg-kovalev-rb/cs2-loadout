# typed: strict

module Demo
  class InventoriesController < ApplicationController
    extend T::Sig

    sig { void }
    def show
      redirect_to(root_path, alert: "Start a demo first.") unless current_demo
    end
  end
end
