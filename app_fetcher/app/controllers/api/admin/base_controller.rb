# typed: strict

require "jwt"

module Api
  module Admin
    class BaseController < ::ApplicationController
      extend T::Sig

      before_action :authenticate_admin_bridge_token!
      rescue_from StandardError, with: :render_internal_server_error
      rescue_from ActiveRecord::RecordNotFound, with: :render_not_found

      private

      sig { returns(String) }
      def current_admin_id
        T.must(@current_admin_id)
      end

      sig { void }
      def authenticate_admin_bridge_token!
        token = request.headers["Authorization"]&.delete_prefix("Bearer ")

        if token.blank?
          render json: { message: "Missing bridge token" }, status: :unauthorized
          return
        end

        payload, = JWT.decode(token, ENV.fetch("APP_ADMIN_BRIDGE_JWT_SECRET"), true, algorithm: "HS256")
        @current_admin_id = T.let(payload.fetch("admin_id"), T.nilable(String))
      rescue JWT::ExpiredSignature, JWT::DecodeError, JWT::VerificationError, KeyError
        render json: { message: "Invalid bridge token" }, status: :unauthorized
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

      sig { params(pagination: Appliers::Pagination, total_count: Integer).returns(T::Hash[Symbol, Integer]) }
      def pagination_meta(pagination, total_count)
        { total_count: total_count, total_pages: pagination.total_pages(total_count) }
      end
    end
  end
end
