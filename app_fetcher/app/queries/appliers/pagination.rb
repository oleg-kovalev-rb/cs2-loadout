# typed: strict

module Appliers
  class Pagination
    extend T::Sig

    DEFAULT_PAGE = T.let(1, Integer)
    DEFAULT_PER_PAGE = T.let(25, Integer)
    MIN_PAGE = T.let(1, Integer)
    MIN_PER_PAGE = T.let(1, Integer)
    MAX_PER_PAGE = T.let(100, Integer)

    sig { returns(Integer) }
    attr_reader :page

    sig { returns(Integer) }
    attr_reader :per_page

    sig { params(raw_page: T.untyped, raw_per_page: T.untyped, default_per_page: Integer).void }
    def initialize(raw_page, raw_per_page, default_per_page: DEFAULT_PER_PAGE)
      @page = T.let(clamp(raw_page, default: DEFAULT_PAGE, min: MIN_PAGE), Integer)
      @per_page = T.let(clamp(raw_per_page, default: default_per_page, min: MIN_PER_PAGE, max: MAX_PER_PAGE), Integer)
    end

    sig { returns(Integer) }
    def offset
      (page - 1) * per_page
    end

    sig { params(total_count: Integer).returns(Integer) }
    def total_pages(total_count)
      total_count.zero? ? 0 : (total_count.to_f / per_page).ceil
    end

    sig { params(scope: ActiveRecord::Relation).returns(ActiveRecord::Relation) }
    def apply(scope)
      scope.limit(per_page).offset(offset)
    end

    private

    sig { params(raw: T.untyped, default: Integer, min: Integer, max: T.nilable(Integer)).returns(Integer) }
    def clamp(raw, default:, min:, max: nil)
      value = [ raw.blank? ? default : raw.to_s.to_i, min ].max
      max ? [ value, max ].min : value
    end
  end
end
