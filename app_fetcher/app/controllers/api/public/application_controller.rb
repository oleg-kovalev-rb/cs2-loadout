# typed: strict

module Api
  module Public
    class ApplicationController < ActionController::API
      extend T::Sig

      rescue_from StandardError, with: :render_internal_server_error

      private

      sig { params(exception: StandardError).void }
      def render_internal_server_error(exception)
        Rails.logger.error("#{exception.class}: #{exception.message}\n#{exception.backtrace&.join("\n")}")
        render json: { message: "Internal error" }, status: :internal_server_error
      end
    end
  end
end
