# typed: strict

module Api
  module Demo
    class InventoryValuesController < BaseController
      extend T::Sig

      sig { void }
      def index
        render json: InventoryValueSerializer.call(demo_dataset.value(period: params[:period])), status: :ok
      end
    end
  end
end
