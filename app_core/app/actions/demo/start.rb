# typed: strict

module Demo
  class Start
    extend T::Sig

    sig { returns(SessionStore::Session) }
    def self.call
      SessionStore.create
    end
  end
end
