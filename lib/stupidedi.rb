# frozen_string_literal: true
require "bigdecimal"
require "time"
require "date"
require "set"

begin
  require "term/ansicolor" if $stdout.tty?
rescue LoadError
  warn "terminal color disabled. gem install term-ansicolor to enable"
end

$:.unshift(File.expand_path("..", __FILE__))

require "ruby/array"
require "ruby/blank"
require "ruby/exception"
require "ruby/hash"
require "ruby/module"
require "ruby/object"
require "ruby/string"
require "ruby/to_d"
require "ruby/to_date"
require "ruby/to_time"
require "ruby/try"

module Stupidedi
  # @todo deprecated
  autoload :Builder,          "stupidedi/builder"

  autoload :Color,            "stupidedi/color"
  autoload :Config,           "stupidedi/config"
  autoload :Either,           "stupidedi/either"
  autoload :Exceptions,       "stupidedi/exceptions"
  autoload :Inspect,          "stupidedi/inspect"
  autoload :Interchanges,     "stupidedi/interchanges"
  autoload :Parser,           "stupidedi/parser"
  autoload :Reader,           "stupidedi/reader"
  autoload :Schema,           "stupidedi/schema"
  autoload :Sets,             "stupidedi/sets"
  autoload :TransactionSets,  "stupidedi/transaction_sets"
  autoload :Values,           "stupidedi/values"
  autoload :Versions,         "stupidedi/versions"
  autoload :Writer,           "stupidedi/writer"
  autoload :Zipper,           "stupidedi/zipper"
  autoload :VERSION,          "stupidedi/version"

  # Top-level namespaces that lived under +Stupidedi+ in the upstream
  # stupidedi gem (the ack/editor subsystem, the +Contrib+ extras, and
  # the +Guides+ implementation-guide tree). tediparse does not ship
  # them; reach for one by name and we surface a helpful error rather
  # than +NameError+.
  REMOVED_TOP_LEVEL = %i[Editor Contrib Guides].freeze
  private_constant :REMOVED_TOP_LEVEL

  def self.const_missing(name)
    if REMOVED_TOP_LEVEL.include?(name.to_sym)
      raise Stupidedi::Exceptions::MissingGrammarError.new("#{self}::#{name}")
    end

    super
  end

  def self.caller(depth = 2)
    if k = ::Kernel.caller.at(depth - 1)
      k.split(":")
    end
  end
end
