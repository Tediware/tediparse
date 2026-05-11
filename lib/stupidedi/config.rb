# frozen_string_literal: true
module Stupidedi
  using Refinements

  class Config
    autoload :CodeListConfig,         "stupidedi/config/code_list_config"
    autoload :EditorConfig,           "stupidedi/config/editor_config"
    autoload :FunctionalGroupConfig,  "stupidedi/config/functional_group_config"
    autoload :InterchangeConfig,      "stupidedi/config/interchange_config"
    autoload :TransactionSetConfig,   "stupidedi/config/transaction_set_config"

    include Inspect

    # @return [InterchangeConfig]
    attr_reader :interchange

    # @return [FunctionalGroupConfig]
    attr_reader :functional_group

    # @return [TransactionSetConfig]
    attr_reader :transaction_set

    # @return [CodeListConfig]
    attr_reader :code_list

    # @return [EditorConfig]
    attr_reader :editor

    def initialize
      @interchange      = InterchangeConfig.new
      @functional_group = FunctionalGroupConfig.new
      @transaction_set  = TransactionSetConfig.new
      @code_list        = CodeListConfig.new
      @editor           = EditorConfig.new
    end

    def customize(&block)
      tap(&block)
    end

    # @return [void]
    def pretty_print(q)
      q.text "Config"
      q.group 2, "(", ")" do
        q.breakable ""

        q.pp @interchange
        q.text ","
        q.breakable

        q.pp @functional_group
        q.text ","
        q.breakable

        q.pp @transaction_set
        q.text ","
        q.breakable

        q.pp @code_list
        q.text ","
        q.breakable

        q.pp @editor
      end
    end
  end

  class << Config
    ###########################################################################
    # @group Constructors

    # Returns an empty Config.
    #
    # tediparse does not ship with X12 grammars or transaction-set definitions
    # — those are X12 IP that the gem is not licensed to redistribute. This
    # method is preserved for source compatibility with upstream stupidedi
    # callers; an empty Config means parser-driven lookups produce a
    # FailureState whose reason is
    # +Stupidedi::Exceptions::MissingGrammarError::DEFAULT_MESSAGE+.
    #
    # Register your own grammar with +#customize+ before parsing. See the
    # README and +spec/support/synthetic/demo.rb+ for an authoring example.
    #
    # @return [Config]
    def default
      new
    end

    # See {.default}. Preserved for source compatibility; returns an empty
    # Config built atop +base+ so existing call sites that compose
    # configurations (e.g. +Config.hipaa(my_base)+) keep working.
    #
    # @return [Config]
    def hipaa(base = default)
      base
    end

    # See {.default}. Preserved for source compatibility; returns the +base+
    # unmodified.
    #
    # @return [Config]
    def contrib(base = default)
      base
    end

    # @endgroup
    ###########################################################################
  end
end
