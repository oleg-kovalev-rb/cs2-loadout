# typed: strict

module Demo
  class Stop
    extend T::Sig

    sig { params(id: String).void }
    def self.call(id)
      SessionStore.delete(id)
    end
  end
end
