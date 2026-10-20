# typed: strict

require "jwt"

module Api
  module Demo
    class BaseController < ::ApplicationController
      extend T::Sig

      AUDIENCE = T.let("demo", String)

      before_action :authenticate_demo_token!

      rescue_from StandardError, with: :render_internal_server_error
      rescue_from ActiveRecord::RecordNotFound, with: :render_not_found
      rescue_from Api::Demo::UnsupportedParamError, with: :render_unsupported_param_error

      private

      sig { returns(Integer) }
      def demo_seed
        T.must(@demo_seed)
      end

      sig { returns(::Demo::Dataset) }
      def demo_dataset
        @demo_dataset ||= T.let(
          ::Demo::Dataset.new(seed: demo_seed),
          T.nilable(::Demo::Dataset)
        )
      end

      sig { void }
      def authenticate_demo_token!
        token = request.headers["Authorization"]&.delete_prefix("Bearer ")
        raise JWT::DecodeError, "Missing demo token" if token.blank?

        payload, = JWT.decode(
          token,
          ENV.fetch("APP_DEMO_JWT_SECRET"),
          true,
          algorithm: "HS256"
        )

        raise JWT::DecodeError, "Invalid audience" unless payload["aud"] == AUDIENCE

        @demo_seed = T.let(Integer(payload.fetch("seed")), T.nilable(Integer))
      rescue JWT::DecodeError, JWT::ExpiredSignature, KeyError, ArgumentError, TypeError
        render json: { message: "Invalid demo token" }, status: :unauthorized
      end

      sig { params(exception: StandardError).void }
      def render_internal_server_error(exception)
        Rails.logger.error("#{exception.class}: #{exception.message}\n#{exception.backtrace&.join("\n")}")
        render json: { message: "Internal error" }, status: :internal_server_error
      end

      sig { params(_exception: ActiveRecord::RecordNotFound).void }
      def render_not_found(_exception)
        render json: { message: "Not found" }, status: :not_found
      end

      sig { params(exception: Api::Demo::UnsupportedParamError).void }
      def render_unsupported_param_error(exception)
        render json: { message: exception.message }, status: :bad_request
      end
    end
  end
end
