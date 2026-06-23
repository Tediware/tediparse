Tediparse Documentation
========================

Tediparse is a library for **parsing, generating, and validating** ASC X12 EDI
documents. It ships the engine — the schema vocabulary, the immutable
parser/state machine, the reader/writer, and the tree cursor — but **not** any
X12 transaction-set grammars: that material is X12 IP you supply or generate.
See the [project README](../README.md) for scope, licensing, and installation.

These pages are the human documentation. They run roughly in the order you'd
use the library: define or generate a grammar, then read, traverse, validate,
and write documents against it. The runnable worked example every page refers to
is the synthetic grammar under `spec/support/synthetic/` (`Synthetic.config`).

Authoring a grammar
-------------------

You bring the grammar; these cover the two ways to get one.

- [Defining](Defining.md) — transcribe a grammar by hand from a purchased X12
  implementation guide (`TableDef`, `LoopDef`, `SegmentDef`, elements).
- [Generating Grammars](Generating-Grammars.md) — generate the whole definition
  tree for a release from licensed ASC X12 Table Data flat files.

Generating documents
--------------------

- [Generating](Generating.md) — build well-formed X12 documents with the
  `BuilderDsl` writer DSL, with validation on every segment.

Reading & parsing
-----------------

- [Tokenizing](Tokenizing.md) — the lexical layer: bytes → segment tokens,
  separators, and positions (no grammar required).
- [Parsing](Parsing.md) — tokens → a typed parse tree, against a registered
  grammar; results, immutability, and non-determinism.
- [Navigating](Navigating.md) — traverse and read values from the parse tree
  (`first`/`find`/`next`/`parent`, the `Either` combinators, and more).

Validating
----------

- [Validating](Validating.md) — the three moments validation happens: while
  generating, while parsing, and when auditing a grammar for ambiguity.

Serializing
-----------

- [Serializing](Serializing.md) — write a parse tree back to X12 text
  (`Writer::Default`) or HTML (`Writer::Claredi`).
