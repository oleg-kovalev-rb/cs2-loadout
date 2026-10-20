# typed: strict

module Api
  module Demo
    class InventoriesController < BaseController
      extend T::Sig

      sig { void }
      def show
        render json: InventorySerializer.call(demo_dataset.items), status: :ok
      end

      sig { void }
      def summary
        render json: InventoryListSerializer.inventory_json(demo_dataset.summary), status: :ok
      end

      sig { void }
      def detail
        render json: InventoryDetailSerializer.call(demo_dataset.details(params)), status: :ok
      end
    end
  end
end
