# frozen_string_literal: true
module Stupidedi
  module Versions
    autoload :Common, "stupidedi/versions/common"

    # Per-era namespaces that lived under +Stupidedi::Versions+ in the
    # upstream stupidedi gem (plus the two long-deprecated
    # +FunctionalGroups+ / +Interchanges+ aliases). tediparse does not ship
    # them; reach for one by name and we surface a helpful error rather
    # than +NameError+.
    REMOVED_ERAS = %i[
      TwoThousandOne ThirtyTen ThirtyForty ThirtyFifty FortyTen FiftyTen
      FunctionalGroups Interchanges
    ].freeze
    private_constant :REMOVED_ERAS

    def self.const_missing(name)
      if REMOVED_ERAS.include?(name.to_sym)
        raise Stupidedi::Exceptions::MissingGrammarError
      end

      super
    end
  end
end
