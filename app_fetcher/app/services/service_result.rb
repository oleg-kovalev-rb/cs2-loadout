# typed: strict

class ServiceResult < T::Struct
  extend T::Generic
  extend T::Sig

  Payload = type_member

  class Status < T::Enum
    enums do
      Ok = new("ok")
      Skipped = new("skipped")
      Failed = new("failed")
    end
  end

  const :status, Status
  const :data, T.nilable(Payload)
  const :error, T.nilable(String)

  sig { returns(T::Boolean) }
  def success?
    status == Status::Ok
  end

  sig { returns(T::Boolean) }
  def skipped?
    status == Status::Skipped
  end

  sig { returns(T::Boolean) }
  def failed?
    status == Status::Failed
  end
end
