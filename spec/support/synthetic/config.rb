# frozen_string_literal: true
require_relative "interchange_def"
require_relative "functional_group_def"
require_relative "demo"

#
# `Synthetic.config` returns a fresh `Stupidedi::Config` wired up to the
# synthetic envelope and the Demo transaction set. Spec helpers that need a
# parser pre-loaded with the synthetic grammar should call this.
#
# Note: the ambiguous demo is not registered here on purpose — the Ambiguity
# validator examines a TransactionSetDef directly, it does not need to be
# resolvable through Config.
#
module Synthetic
  class << self
    def config
      Stupidedi::Config.new.customize do |c|
        c.interchange.customize do |x|
          x.register("DEMO01", Synthetic::InterchangeDef)
        end
        c.functional_group.customize do |x|
          x.register("DEMO01", Synthetic::FunctionalGroupDef)
        end
        c.transaction_set.customize do |x|
          x.register("DEMO01", "ZZ", "100", Synthetic::Demo)
        end
      end
    end
  end
end
