# frozen_string_literal: true
module Stupidedi
  module Exceptions
    #
    # Raised when application code reaches for a grammar that tediparse does
    # not ship. tediparse is the parser/writer engine only; transaction-set
    # grammars, code lists, and implementation guides are not bundled (they
    # are X12 IP). Users must register their own grammar against
    # +Stupidedi::Config+ before parsing.
    #
    # Three places raise this:
    #
    # 1. +Stupidedi::Interchanges.const_missing+,
    #    +Stupidedi::Versions.const_missing+, and
    #    +Stupidedi::TransactionSets.const_missing+ raise it when application
    #    code references a per-era constant by name
    #    (e.g. +Stupidedi::Versions::FiftyTen+).
    #
    # 2. The three envelope parser states (+InterchangeState+,
    #    +FunctionalGroupState+, +TransactionSetState+) surface this message
    #    as the +reason+ on +InvalidSegmentVal+ when the relevant config
    #    sub-registry is empty. The parser itself does not raise — it
    #    produces a +FailureState+ — but the message is the same so users
    #    see one consistent UX whether they hit a bare +const_missing+ or a
    #    parse failure.
    #
    class MissingGrammarError < StupidediError
      DEFAULT_MESSAGE =
        "tediparse does not ship with X12 grammars or transaction-set " \
        "definitions. Register your own grammar against Stupidedi::Config " \
        "before parsing — see the README for an authoring example."

      # @param context [String, nil]
      #   When given, appended to the default message as " (while resolving
      #   <context>)". Used by the +const_missing+ hooks to name the
      #   per-era constant the caller reached for; left nil at parser-state
      #   callsites where no constant name is in play.
      def initialize(context = nil)
        message =
          if context
            "#{DEFAULT_MESSAGE} (while resolving #{context})"
          else
            DEFAULT_MESSAGE
          end

        super(message)
      end
    end
  end
end
