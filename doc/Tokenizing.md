Tokenizing X12
==============

Tokenizing is the first stage of reading an X12 document: turning a stream of
bytes into a sequence of **segment tokens**, before any grammar is consulted.
The reader knows about X12's *lexical* structure — segments, elements,
components, repetitions, and the four delimiters — but nothing about what a
particular transaction set means. That separation is deliberate: you can
tokenize a document with no grammar registered at all, and the same tokenizer
feeds the grammar-aware [parser](Parsing.md).

The reader lives under `Stupidedi::Reader`. To go from tokens to a typed parse
tree, see [Parsing](Parsing.md); this page covers the lexical layer only.

Building a reader
-----------------

`Stupidedi::Reader.build(input)` returns a tokenizer. `input` may be a `String`,
an `IO` (e.g. an open `File`), or any `Stupidedi::Reader::Input`:

```ruby
require "tediparse"

input  = File.open("path/to/your.edi", :encoding => "ISO-8859-1")
reader = Stupidedi::Reader.build(input)   # => Reader::StreamReader
```

X12 is an ISO-8859-1 (Latin-1) format, not UTF-8 — open files with that
encoding to avoid corrupting extended characters.

Two phases: StreamReader and TokenReader
----------------------------------------

Tokenizing happens in two phases, because the delimiters are not known until
the `ISA` segment has been read:

- **`StreamReader`** is what `Reader.build` returns. It skips any out-of-band
  data (whitespace, line breaks, or other content between interchanges) until
  it finds a literal `ISA`, then tokenizes that fixed-width segment. The `ISA`
  segment is special: its layout is fixed by the standard, so the reader can
  parse it byte-for-byte even before it knows the delimiters.
- **`TokenReader`** takes over once `ISA` has been read. It is delimiter-aware
  and tokenizes every following segment (`GS`, `ST`, …) using the separators
  discovered from `ISA`.

You rarely name these classes directly — you call `read_segment` and thread the
reader it hands back, and the transition from `StreamReader` to `TokenReader`
happens for you.

Reading segments
----------------

A reader has no `each`; you pull one segment at a time with `read_segment`,
which returns an [`Either`](Navigating.md) wrapping the token **and the next
reader**. Thread that reader through `Either#flatmap` to consume the stream,
stopping when the `Either` becomes a failure (end of input):

```ruby
reader = Stupidedi::Reader.build(input)

drain = lambda do |r|
  r.read_segment.flatmap do |segment_tok, next_reader|
    puts segment_tok.id              # => :ISA, :GS, :ST, ...
    drain.call(next_reader)          # recurse on the new reader
  end
end

drain.call(reader)
```

Each success yields a `Reader::SegmentTok` plus the next reader; the previous
reader is untouched (the readers are immutable, like the rest of the library).
The parser's own read loop is exactly this pattern — see
`lib/stupidedi/parser/generation.rb` for the production version.

Tokens
------

- **`SegmentTok`** — one segment. `#id` is the segment identifier as a `Symbol`
  (`:ISA`, `:ST`, …), `#element_toks` is the ordered list of element tokens,
  and `#position` is where it started in the input (see below).
- **`SimpleElementTok`** — one ordinary element; `#value` is its string value.
- **`CompositeElementTok`**, **`ComponentElementTok`**, **`RepeatedElementTok`**
  — composites, their components, and repeated elements, when the grammar (or
  the raw delimiters) calls for them.

Without a grammar, the `TokenReader` treats every element as simple — it has no
way to know which elements are composite or repeating. Supply a grammar through
the [parser](Parsing.md) to get composite/repeated structure.

Separators
----------

`Stupidedi::Reader::Separators` carries the four X12 delimiters, each available
as an accessor:

| Accessor      | X12 role                 | Typical character |
| ------------- | ------------------------ | ----------------- |
| `#element`    | separates elements       | `*`               |
| `#component`  | separates components     | `:`               |
| `#repetition` | separates repetitions    | `^`               |
| `#segment`    | terminates a segment     | `~`               |

The delimiters are **discovered from the document**, not assumed — handling an
unexpected choice (say, swapping `:` and `~`) is one of the things a hand-rolled
parser usually gets wrong. They become known in stages:

1. While reading `ISA`, `StreamReader` takes the character immediately after
   `ISA` as the **element** separator, and the character after the 16th element
   as the **segment** terminator.
2. The **component** and **repetition** separators are version-dependent and are
   resolved only when the parser enters the interchange envelope and the
   grammar's `InterchangeDef#separators(isa)` reads them out of `ISA16` and
   `ISA11`.

So **standalone tokenizing (no grammar) gives you the element and segment
delimiters**; full component/repetition resolution needs the envelope grammar,
i.e. the [parser](Parsing.md). You can also construct separators explicitly —
`Separators.default` is `(":", "^", "*", "~")` — which the [writer](Serializing.md)
uses to serialize a tree back to X12.

Positions
---------

Every token carries a `Stupidedi::Reader::Position` (`#position`) recording
where it began: `#offset`, `#line`, `#column`, and `#path`. Positions are what
make error messages actionable — when the [parser](Parsing.md) reports a
failure, `result.position` points at the exact spot in the input.

Where to go next
----------------

- [Parsing](Parsing.md) — feed the tokens to a grammar and build a typed parse
  tree.
- [Navigating](Navigating.md) — traverse the tree the parser builds.
- [Serializing](Serializing.md) — turn a tree back into X12 text.
