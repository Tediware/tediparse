module Stupidedi
  module TransactionSets
    autoload :Builder,    "stupidedi/transaction_sets/builder"
    autoload :Validation, "stupidedi/transaction_sets/validation"
    autoload :Common,     "stupidedi/transaction_sets/common"

    # Per-era transaction-set namespaces that lived under
    # +Stupidedi::TransactionSets+ in the upstream stupidedi gem. tediparse
    # does not ship them; reach for one by name and we surface a helpful
    # error rather than +NameError+. Deeper guide names (X222A1, etc.) are
    # nested under these eras, so catching at the era level is sufficient.
    REMOVED_ERAS = %i[
      TwoThousandOne ThirtyTen ThirtyForty ThirtyFifty FortyTen FiftyTen
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
