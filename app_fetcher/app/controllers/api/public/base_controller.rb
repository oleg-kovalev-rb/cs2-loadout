# typed: strict

module Api
  module Public
    class BaseController < ::ApplicationController
      extend T::Sig

      rescue_from StandardError, with: :render_internal_server_error
      rescue_from Api::Public::UnsupportedParamError, with: :render_unsupported_param_error
      rescue_from ActiveRecord::RecordNotFound, with: :render_not_found

      private

      sig { params(exception: Api::Public::UnsupportedParamError).void }
      def render_unsupported_param_error(exception)
        render json: { message: exception.message }, status: :bad_request
      end

      sig { params(exception: ActiveRecord::RecordNotFound).void }
      def render_not_found(exception)
        render json: { message: "Inventory not found" }, status: :not_found
      end

      sig { params(exception: StandardError).void }
      def render_internal_server_error(exception)
        Rails.logger.error("#{exception.class}: #{exception.message}\n#{exception.backtrace&.join("\n")}")
        render json: { message: "Internal error" }, status: :internal_server_error
      end
    end
  end
end
