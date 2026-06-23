Serializing X12
===============

Serializing is the inverse of [parsing](Parsing.md): taking a parse tree and
writing it back out. Once you have a tree — whether you
[generated](Generating.md) it with the builder DSL or [parsed](Parsing.md) it
from input — you serialize it with one of the writers under
`Stupidedi::Writer`:

- **`Writer::Default`** writes X12 text using a set of [separators](Tokenizing.md).
- **`Writer::Claredi`** writes a formatted HTML rendering of the tree.

Getting a tree to serialize
---------------------------

Both writers take the **root node** of the value tree. You reach it through the
state machine's zipper, `machine.zipper.fetch.root`, in either of the two ways a
tree comes to exist:

```ruby
# (a) After generating with the builder DSL
b = Stupidedi::Parser::BuilderDsl.build(config)
b.ISA(...); b.GS(...); b.ST(...); # ... ; b.SE(...); b.GE(...); b.IEA(...)
root = b.machine.zipper.fetch.root

# (b) After parsing input
machine, _result = Stupidedi::Parser.build(config).read(Stupidedi::Reader.build(input))
root = machine.zipper.fetch.root
```

`zipper` returns an [`Either`](Navigating.md); `.fetch` unwraps it (or raises if
the tree is empty) and `.root` rewinds to the top of the tree.

Writing X12 text
----------------

`Writer::Default.new(root, separators)` writes the tree as X12, using the
separators you pass for the element, component, repetition, and segment
delimiters. `#write` returns the serialized `String`:

```ruby
separators = Stupidedi::Reader::Separators.new(":", "^", "*", "~")
#                                              comp  rep  elem  seg

x12 = Stupidedi::Writer::Default.new(root, separators).write
puts x12
```

You can serialize with **different separators than the input used** — the writer
re-stamps the envelope's `ISA11`/`ISA16` to match the separators you request, so
the output is internally consistent. Round-tripping with the *same* separators
reproduces the original document (the synthetic smoke tests in
`spec/lib/stupidedi/synthetic/smoke_spec.rb` assert this byte-for-byte).

The role of separators
----------------------

`Stupidedi::Reader::Separators` (the same class the [reader](Tokenizing.md)
discovers from `ISA`) drives every delimiter the writer emits. A few rules the
writer enforces:

- The segment terminator and element separator must be non-blank when writing an
  interchange — a blank one raises `Stupidedi::Exceptions::OutputError`
  (`"separators.segment cannot be blank"`).
- A separator character must not collide with the data: if a value contains a
  character you've chosen as a delimiter, the writer raises `OutputError`
  (`'characters "~" occur as data'`) rather than emit an unparseable document.

`Separators.default` (`(":", "^", "*", "~")`) is a convenient starting point.

Writing HTML
------------

`Writer::Claredi` renders the tree as an HTML document — useful for inspection
or display. It takes just the root node (no separators) and `#write` returns the
output (an `IO`/`StringIO` you can read or write to a file):

```ruby
File.open("output.html", "w") do |f|
  f.write Stupidedi::Writer::Claredi.new(root).write.string
end
```

Serializing a subtree
---------------------

The writers don't require the interchange root — you can serialize any subtree.
Navigate to the node you want, take its zipper, and write that:

```ruby
st = b.machine.first.flatmap { |m| m.sequence(:GS, :ST) }.fetch.zipper.fetch
fragment = Stupidedi::Writer::Default.new(st, separators).write
```

Where to go next
----------------

- [Generating](Generating.md) — build a tree to serialize.
- [Parsing](Parsing.md) — parse input into a tree to round-trip.
- [Navigating](Navigating.md) — locate the subtree you want to write.
