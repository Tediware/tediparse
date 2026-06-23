Validating X12
==============

Validation in tediparse happens at three distinct moments, and it helps to keep
them separate because they report problems in different ways:

1. **Generating** a document — the writer DSL validates each segment as you
   build it and *raises* on the first violation.
2. **Parsing** a document — segments that don't fit the grammar become
   *invalid-value nodes in the tree* rather than exceptions, so one bad segment
   doesn't abort the read.
3. **Auditing a grammar** — the `Ambiguity` analyzer statically checks a
   transaction-set definition for places the parser couldn't deterministically
   resolve, and raises before you ship the grammar.

This page covers all three. The examples use `Synthetic.config` and the
synthetic grammar in `spec/support/synthetic/`; substitute your own grammar.

Validation while generating
---------------------------

`Stupidedi::Parser::BuilderDsl` validates incrementally. Built with
`strict = true` (the default), it checks each segment the instant you add it and
raises `Stupidedi::Exceptions::ParseError` the moment your code violates the
specification — with a stack trace pointing at the offending call, not after the
whole document is assembled.

```ruby
b = Stupidedi::Parser::BuilderDsl.build(config)   # strict: true by default

b.ISA(...)
b.GS(...)
b.ST("100", "0001")
b.HH("Synthetic heading text")
# b.IT("P:item-1", "3", "125.5")   # would raise ParseError: required segment
                                    #   missing, value not allowed, too long, etc.
```

What `critique` checks as each node completes
(`lib/stupidedi/parser/builder_dsl.rb`):

- **Element type** — the value is valid for its element type (numeric, date,
  time, …).
- **Requirement** — a required element/segment isn't blank; a forbidden
  ("not used") one isn't present.
- **Code lists** — an `ID` element's value is one of its allowed values.
- **Length** — the value isn't shorter or longer than the element's min/max.
- **Syntax notes** — paired/conditional/exclusion rules (e.g. the `P` paired
  note) are satisfied on composites and segments.
- **Occurrence bounds** — a segment or loop occurs at least the required number
  of times and no more than its repeat count allows.

Passing `strict = false` to `BuilderDsl.build(config, false)` skips these checks
— useful when you deliberately need to emit a non-conforming document for a
trading partner that demands one.

Validation while parsing
------------------------

When *reading* (see [Parsing](Parsing.md)), the parser is forgiving by design: a
segment that can't be placed in the grammar — or an envelope whose grammar isn't
registered — becomes an `InvalidSegmentVal` / `InvalidEnvelopeVal` node in the
tree instead of raising. `result.fatal?` stays `false`; the document parses, and
you inspect the tree to find what didn't fit.

Walk the value tree and collect the invalid nodes:

```ruby
machine, result = Stupidedi::Parser.build(config).read(Stupidedi::Reader.build(input))

def collect_failures(machine)
  failures = []
  walk = lambda do |z|
    node = z.node
    failures << node if node.is_a?(Stupidedi::Values::InvalidSegmentVal) ||
                        node.is_a?(Stupidedi::Values::InvalidEnvelopeVal)
    z.children.each { |c| walk.call(c) } if z.respond_to?(:children) && !z.leaf?
  end
  walk.call(machine.zipper.fetch.root)
  failures
end

failures = collect_failures(machine)
```

An `InvalidSegmentVal` carries the reason it couldn't be placed and the original
segment token (with its [position](Tokenizing.md)). A transaction set whose
`ST01` code isn't registered, for example, yields an `InvalidSegmentVal` at the
`ST` segment carrying the missing-grammar message (see
[Parsing → Missing grammar](Parsing.md)). This is the pattern the smoke tests in
`spec/lib/stupidedi/synthetic/smoke_spec.rb` use.

Auditing a grammar for ambiguity
--------------------------------

The third kind of validation is about the *grammar itself*, not a document. A
grammar is ambiguous when the parser, reading a given segment, can't
deterministically decide which slot it fills — for instance two sibling loops
that open on the same segment with overlapping allowed values on the
discriminating element. Ambiguity is what forces the parser into the
multiple-hypothesis state described in [Parsing](Parsing.md); catching it at the
definition stage is far better than discovering it at runtime.

`Stupidedi::TransactionSets::Validation::Ambiguity` audits a `TransactionSetDef`
and raises `Stupidedi::Exceptions::InvalidSchemaError` when it finds an
unresolvable choice:

```ruby
Stupidedi::TransactionSets::Validation::Ambiguity.build(
  transaction_set_def,    # the TransactionSetDef to audit
  functional_group_def,   # the GS/GE envelope it lives in
  interchange_def         # the ISA/IEA envelope
).audit
# raises InvalidSchemaError if the definition is ambiguous
```

The synthetic suite exercises this against a deliberately ambiguous grammar —
`spec/support/synthetic/ambiguous_demo.rb` defines two `LO` loops at the same
position that both accept the discriminator value `"P"`, and
`spec/lib/stupidedi/synthetic/ambiguity_spec.rb` asserts the audit raises an
`InvalidSchemaError` whose message names the overlapping `ValueBased` choice:

```ruby
Stupidedi::TransactionSets::Validation::Ambiguity.build(
  Synthetic::AmbiguousDemo,
  Synthetic::FunctionalGroupDef,
  Synthetic::InterchangeDef
).audit
#=> raises InvalidSchemaError: ... overlapping ... ValueBased ...
```

Run the audit over your transaction-set definitions in your own test suite to
catch ambiguity before it reaches a parser.

Where to go next
----------------

- [Generating](Generating.md) — the full writer DSL these checks guard.
- [Parsing](Parsing.md) — how invalid nodes get into the tree.
- [Navigating](Navigating.md) — traversing a tree that may contain invalid nodes.
