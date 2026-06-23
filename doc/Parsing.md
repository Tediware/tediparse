Parsing X12
===========

Parsing turns the token stream from the [reader](Tokenizing.md) into a typed
**parse tree** — a tree of interchange, functional-group, transaction-set,
table, loop, segment, and element values — by walking it against a grammar you
have registered. Where [tokenizing](Tokenizing.md) is purely lexical, parsing is
grammar-aware: it knows which segments may occur where, which loops they open,
and which elements are composite or repeating.

This page covers getting from input to a tree. Once you have the tree, see
[Navigating](Navigating.md) to traverse it and [Serializing](Serializing.md) to
write it back out.

You bring the grammar
---------------------

Tediparse ships the engine, not the grammars. Before parsing real documents you
must register your own grammar against a `Stupidedi::Config` — see
[Defining](Defining.md) (authoring by hand) or
[Generating-Grammars](Generating-Grammars.md) (generating from ASC X12 Table
Data). The examples below use `Synthetic.config`, the worked grammar in
`spec/support/synthetic/`; substitute your own populated config (e.g.
`MyApp::EDI.config`).

Building a parser and reading input
-----------------------------------

`Stupidedi::Parser.build(config)` returns a `Parser::StateMachine`. Feed it a
[reader](Tokenizing.md) with `#read`, which returns a **`[machine, result]`
pair**: the updated state machine (now holding the parse tree) and a
`Reader::Result` describing how the read ended.

```ruby
require "tediparse"

config = Synthetic.config                       # your populated Stupidedi::Config
parser = Stupidedi::Parser.build(config)

input  = File.read("path/to/your.edi")          # or File.open(..., :encoding => "ISO-8859-1")
machine, result = parser.read(Stupidedi::Reader.build(input))
```

Both the parser and the input are values: `read` does not mutate `parser`, it
returns a new machine. The original is still usable, which is what makes the
[navigation](Navigating.md) combinators safe to chain.

Checking the result
--------------------

The second element of the pair is a `Reader::Result`. Ask it whether the read
ended fatally, and use `explain` to surface the reason with its position:

```ruby
if result.fatal?
  result.explain { |reason| raise "#{reason} at #{result.position.inspect}" }
end
```

`result.position` (offset / line / column) points into the input, so errors are
locatable. A non-fatal result is the normal end-of-input case.

What "fatal" does and doesn't mean
----------------------------------

A non-fatal result does **not** mean the document was fully valid — it means
tokenizing and the overall walk completed. Individual segments that could not be
placed in the grammar are recorded *in the tree* as `InvalidSegmentVal` /
`InvalidEnvelopeVal` nodes rather than aborting the parse. Walk the tree to find
them; see [Validating](Validating.md) for how to collect and interpret these.

Missing grammar
---------------

If you parse a document whose interchange, functional-group, or transaction-set
identifiers are not registered on the config, the parser does **not** raise — it
produces a `FailureState` whose reason is
`Stupidedi::Exceptions::MissingGrammarError::DEFAULT_MESSAGE` (a pointer to
register a grammar). That surfaces as an `InvalidSegmentVal` in the tree at the
envelope segment that couldn't be resolved. So an empty or partial config yields
locatable failures, not a stack trace. (Reaching for a removed per-era constant
like `Stupidedi::Versions::FiftyTen` in *code*, by contrast, raises
`MissingGrammarError` directly.)

Immutability and non-determinism
--------------------------------

The state machine is immutable and may track **more than one parse hypothesis at
once**. Internally `machine.active` is a list of cursors — when the grammar is
momentarily ambiguous (a segment that could open more than one loop, say), the
parser keeps every live interpretation rather than guessing. `machine` answers
`#deterministic?` with `false` while more than one hypothesis is live.

`read` accepts a `:nondeterminism` option capping how many simultaneous
hypotheses are tolerated (**default `1`**). Exceeding the cap ends the read with
a fatal result ("too much non-determinism"):

```ruby
# Allow up to 8 concurrent parse hypotheses before giving up
machine, result = parser.read(Stupidedi::Reader.build(input), :nondeterminism => 8)
```

Most well-formed documents stay deterministic; raise the limit only for grammars
that are genuinely ambiguous at points the input later disambiguates. See
[Navigating → Non-determinism](Navigating.md) for how traversal behaves while
multiple trees are live, and [Validating](Validating.md) for catching ambiguity
in a *grammar definition* up front.

Getting at the tree
-------------------

The parse tree hangs off the machine. `machine.zipper` returns an
[`Either`](Navigating.md) wrapping a cursor at the root of the value tree;
`machine.zipper.fetch.root` gives you the root node (e.g. for the
[writer](Serializing.md)). In practice you navigate with the higher-level
combinators rather than touching the zipper directly:

```ruby
machine.first
  .flatmap { |m| m.find(:GS) }
  .flatmap { |m| m.find(:ST) }
  .tap     { |m| puts m.segment.fetch.node.id }
```

From here, traversal is its own topic — continue with
[Navigating the Parse Tree](Navigating.md).

Where to go next
----------------

- [Navigating](Navigating.md) — find, iterate, and read values from the tree.
- [Validating](Validating.md) — interpret invalid nodes and check grammars.
- [Serializing](Serializing.md) — write a tree back to X12 text.
