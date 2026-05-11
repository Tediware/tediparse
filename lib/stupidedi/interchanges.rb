# frozen_string_literal: true
module Stupidedi
  module Interchanges
    autoload :ElementTypes, "stupidedi/interchanges/element_types"

    # Per-era envelope namespaces that lived under +Stupidedi::Interchanges+
    # in the upstream stupidedi gem. tediparse does not ship them; if user
    # code references one by name we surface a helpful error rather than the
    # bare +NameError+ Ruby would raise for an undefined constant.
    REMOVED_ERAS = %i[TwoHundred ThreeHundred FourHundred FourOhOne FiveOhOne].freeze
    private_constant :REMOVED_ERAS

    def self.const_missing(name)
      if REMOVED_ERAS.include?(name.to_sym)
        raise Stupidedi::Exceptions::MissingGrammarError.new("#{self}::#{name}")
      end

      super
    end
  end
end
