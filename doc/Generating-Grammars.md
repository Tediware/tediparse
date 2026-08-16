Generating Grammars from X12 Table Data
=======================================

> **"Generating" means two different things in this project.** This page is
> about *generating the grammar* — turning the ASC X12 standard into the Ruby
> definition files the engine walks. [Generating.md](Generating.md) is about
> *generating X12 documents* — emitting EDI with the writer once you already
> have a grammar. If you want to produce an 837 or a 204, you want the other
> page.

There are two ways to get a grammar that the engine can use:

1. **Author it by hand** — transcribe a purchased implementation guide into
   `SegmentDef` / `LoopDef` / `TransactionSetDef` values. See
   [Defining.md](Defining.md). This is fine for a handful of segments, but a
   full transaction set is hundreds of definitions.
2. **Generate it from ASC X12 Table Data** — feed the official flat-file
   distribution to the generator and it emits the whole definition tree for a
   release. This page covers that path.

Both produce the same thing: Ruby source that builds `Stupidedi::Schema`
objects, registered against a `Stupidedi::Config`. Generation is just
automation over the hand-authoring you would otherwise do.

The IP boundary
---------------

**The gem ships the generation *machine* only.** The X12 Table Data it reads
is licensed X12 IP that you supply, and the grammar files it writes are a
derivative of that IP that belong to you. Neither the input nor the output
ships with tediparse.

The committed fixture under `spec/support/generation/table_data/` is a small
*synthetic* grammar in the same flat-file format — fabricated structure used
to test the generator — not real X12 content.

Input: the ASC X12 Table Data distribution
-------------------------------------------

To obtain the Table Data you need an **ASC X12 license**; with one in hand you
can download the distribution from <https://ecommerce.x12.org/downloads>.

The Table Data is a set of CSV-shaped `.TXT` files, one header/detail pair per
kind of definition, plus a free-form file:

| File           | Holds                                              |
| -------------- | -------------------------------------------------- |
| `ELEHEAD` / `ELEDETL` | simple data elements (type, lengths, code lists) |
| `COMHEAD` / `COMDETL` | composite elements and their component uses |
| `SEGHEAD` / `SEGDETL` | segments and their ordered element uses     |
| `SETHEAD` / `SETDETL` | transaction sets and their table/loop/segment structure |
| `FREEFORM`            | longer prose (segment/element notes)        |

Point `--table-data` at the directory holding these files for one release.

The CLI
-------

The gem ships one executable, `bin/tediparse`:

```sh
# Generate the full grammar tree for a release into ./lib
tediparse generate --release 005010 \
  --table-data vendor/x12/table_data/005010 \
  --out lib

# Preview without writing anything
tediparse generate --release 005010 \
  --table-data vendor/x12/table_data/005010 \
  --out lib --dry-run

# Emit into a custom root module (default is Edi)
tediparse generate --release 005010 \
  --table-data vendor/x12/table_data/005010 \
  --out lib --namespace Acme

# Also emit a single-require entry file (for non-autoloader setups)
tediparse generate --release 005010 \
  --table-data vendor/x12/table_data/005010 \
  --out lib --master-loader

# Rebuild the whole-tree aggregation files for an existing tree
tediparse register --out lib
```

Supported releases: `003060`, `004010`, `004060`, `005010`, `006010`,
`007010`, `008010`. An unsupported release code is rejected before anything
is read.

From Ruby
---------

The CLI is a thin wrapper over a facade you can call directly — useful from a
Rake task:

```ruby
Stupidedi::Schema::Generation.run(
  table_data:    "vendor/x12/table_data/005010",
  release:       "005010",
  out:           "lib",
  namespace:     "Edi",   # root module for the emitted code (default: "Edi")
  master_loader: false,   # also emit a single-require entry file?
  write:         true,    # false = dry run (returns results, writes nothing)
  logger:        ->(msg) { puts msg }
)

# Rebuild only the whole-tree artifacts (registration + master loader if present)
Stupidedi::Schema::Generation.register(out: "lib")
```

`run` returns one `Result` per file (`path`, `relative_path`, `content`,
`written`), so a dry run gives you the full generated source to diff or
inspect without touching disk. The whole release is staged in a tempdir first
and copied into `out` in one step only on success, so a failure partway
through never leaves a half-written tree.

The output tree
---------------

For `--release 005010 --namespace Edi --out lib`, the generator writes
(`005010` → the `FiftyTen` version module → the `fifty_ten` path):

```
lib/
  edi/
    fifty_ten/
      element_reqs.rb          # aliases Mandatory/Optional/Relational
      element_types.rb         # aliases the element type primitives
      segment_reqs.rb          # aliases the segment requirement enums
      syntax_notes.rb          # aliases the P/R/C/E/L syntax-note builders
      element_defs.rb          # every simple + composite element for the release
      segment_defs.rb          # every segment, incl. ISA/IEA/GS/GE/TA1
      functional_group_def.rb  # the GS/GE envelope
      standards/
        <transaction_set>.rb   # one file per transaction set
    fifty_ten.rb               # version loader: requires this version's files
    interchanges/
      five_oh_one.rb           # the ISA/IEA envelope (named by ISA version code)
    stupidedi_registration.rb  # wires every release in the tree onto a Config
  edi.rb                       # master loader — only with --master-loader
```

- The four small `*_reqs` / `*_types` / `syntax_notes` modules just alias
  common `Stupidedi` types into the version namespace so the bulky files can
  use short names.
- `element_defs.rb` and `segment_defs.rb` are the bulk of the grammar.
- `standards/*.rb` are the transaction-set definitions — these are what you
  register per `(version, functional id, transaction code)`.
- `interchanges/` is **shared across releases** in the tree and named by the
  ISA12 version code (`00501` → `five_oh_one`), not by the release module.
- `stupidedi_registration.rb` is the entry point that builds a populated
  `Config` for everything in the tree (see "Using the grammar" below).

Loading the generated code
---------------------------

By default the tree is meant to be picked up by your application's autoloader
(Rails / Zeitwerk): the file/constant layout follows the `edi/fifty_ten/...`
convention, so `Edi::FiftyTen::SegmentDefs` resolves on demand.

If you are **not** using an autoloader, pass `--master-loader` (or
`master_loader: true`). That emits a single `edi.rb` (named after the
namespace) which `require`s the whole tree in dependency order, so a plain
`require "edi"` loads everything.

Multiple releases in one tree
-----------------------------

You can keep several releases side by side under one `out`. Generating an
additional release **preserves** the ones already present:
`stupidedi_registration.rb` (and the master loader, if any) are whole-tree
artifacts — every run rebuilds them to cover every release found in `out`, not
just the one you just generated. The regenerated release's own directory is
replaced wholesale (so a shrunk transaction-set list doesn't leave orphans),
while other releases and the shared `interchanges/` directory are left alone.

If you add or remove a release by other means and need to refresh just the
aggregation files, run `tediparse register --out lib` (or
`Stupidedi::Schema::Generation.register(out: "lib")`).

Using the generated grammar
----------------------------

The generated `stupidedi_registration.rb` does the wiring for you: it returns
a `Stupidedi::Config` with every release's interchange, functional group, and
transaction sets registered. Load the tree, get the config, and hand it to the
parser or writer exactly as you would a hand-authored one:

```ruby
require "edi"   # or rely on your autoloader

config = Edi.config            # populated Stupidedi::Config from stupidedi_registration.rb

parser = Stupidedi::Parser.build(config)
# ... parse, navigate (see Navigating.md)

b = Stupidedi::Parser::BuilderDsl.build(config)
# ... generate documents (see Generating.md)
```

From here the generated grammar is indistinguishable from one you wrote by
hand. Continue with [Generating.md](Generating.md) to emit documents and
[Navigating.md](Navigating.md) to read and traverse them.

How it works
------------

Generation is two layers with a plain-struct seam between them
(`lib/stupidedi/schema/generation/`):

- **Layer A — `flat_file_reader.rb`** parses the `.TXT` distribution into the
  plain value objects in `models.rb` (`Release`, `Element`, `Segment`,
  `TransactionSet`, `LoopDefinition`, …). It carries no database or Ruby-source
  concerns — any source that builds objects with the same shape can drive the
  next layer.
- **Layer B — the generators** (`element_generator.rb`, `segment_generator.rb`,
  `definition_generator.rb`, `functional_group_generator.rb`,
  `interchange_generator.rb`, `module_loader_generator.rb`,
  `registration_generator.rb`, `support_modules_generator.rb`) consume those
  structs and emit the Ruby source above. `runner.rb` orchestrates a full
  release; `bin/tediparse` is the CLI over it.

`spec/lib/stupidedi/schema/generation_spec.rb` round-trips the synthetic
fixture through the reader, the generators, and a child-process load that
builds real engine objects — so it's also a worked example of what each layer
produces.

Fidelity notes
--------------

A few details the generator carries through from the standard that are easy to
miss:

- **Element repeat counts** come from the SEGDETL repetition column: a numeric
  count becomes `RepeatCount.bounded(n)`, the unbounded marker (`>1`) becomes
  `RepeatCount.unbounded`, and a non-repeating use is `bounded(1)`.
- **The repetition separator** (ISA11 / element I65) is re-stamped in the
  generated interchange's `replace_separators` on releases that use one, so the
  writer round-trips it.
- **Higher-precision numeric types** (`N3`, `N5`, `N7`, `N8`, `N9`, …) all map
  to the engine's `Nn`, which accepts arbitrary implied-decimal precision.
