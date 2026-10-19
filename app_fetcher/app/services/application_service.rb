# typed: strict

class ApplicationService
  extend T::Sig

  class Result < T::Struct
    extend T::Generic
    extend T::Sig

    Payload = type_member(:out)

    class Status < T::Enum
      enums do
        Success = new("success")
        Skipped = new("skipped")
        Failure = new("failure")
      end
    end

    const :status, Status
    const :data, T.nilable(Payload)
    const :error, T.nilable(String)

    sig { returns(T::Boolean) }
    def success?
      status == Status::Success
    end

    sig { returns(T::Boolean) }
    def skipped?
      status == Status::Skipped
    end

    sig { returns(T::Boolean) }
    def failed?
      status == Status::Failure
    end
  end

  class << self
    extend T::Sig

    private

    sig do
      type_parameters(:Payload)
        .params(data: T.type_parameter(:Payload))
        .returns(Result[T.type_parameter(:Payload)])
    end
    def success(data)
      Result[T.untyped].new(status: Result::Status::Success, data: data, error: nil)
    end

    sig { params(error: String).returns(Result[T.noreturn]) }
    def failure(error)
      Result[T.untyped].new(status: Result::Status::Failure, data: nil, error: error)
    end

    sig { returns(Result[T.noreturn]) }
    def skipped
      Result[T.untyped].new(status: Result::Status::Skipped, data: nil, error: nil)
    end
  end
end
