# typed: strict

require "jwt"

module Api
  module V1
    class BaseController < ::ApplicationController
      extend T::Sig

      before_action :authenticate_bridge_token!
      rescue_from StandardError, with: :render_internal_server_error
      rescue_from Api::V1::UnsupportedParamError, with: :render_unsupported_param_error

      private

      sig { returns(String) }
      def current_steam_id
        T.must(@current_steam_id)
      end

      sig { void }
      def authenticate_bridge_token!
        token = request.headers["Authorization"]&.delete_prefix("Bearer ")

        if token.blank?
          render json: { message: "Missing bridge token" }, status: :unauthorized
          return
        end

        payload, = JWT.decode(token, ENV.fetch("APP_BRIDGE_JWT_SECRET"), true, algorithm: "HS256")
        steam_id = payload.fetch("steam_id")
        raise JWT::DecodeError, "Invalid steam_id claim" unless steam_id.is_a?(String)

        @current_steam_id = T.let(steam_id, T.nilable(String))
      rescue JWT::ExpiredSignature, JWT::DecodeError, JWT::VerificationError, KeyError
        render json: { message: "Invalid bridge token" }, status: :unauthorized
      end

      sig { params(exception: Api::V1::UnsupportedParamError).void }
      def render_unsupported_param_error(exception)
        render json: { message: exception.message }, status: :bad_request
      end

      sig { params(exception: StandardError).void }
      def render_internal_server_error(exception)
        Rails.logger.error("#{exception.class}: #{exception.message}\n#{exception.backtrace&.join("\n")}")
        render json: { message: "Internal error" }, status: :internal_server_error
      end
    end
  end
end
