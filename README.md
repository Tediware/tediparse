# Tediparse

- [GitHub project](https://github.com/Tediware/tediparse)
- [Human Documentation](https://github.com/Tediware/tediparse/tree/master/doc)

Tediparse is a library for **parsing, generating, and validating** ASC X12 EDI
documents. You bring the X12 transaction-set grammar; the library walks it.
Very roughly, it's jQuery for EDI — once you've supplied the schema.

For those unfamiliar with ASC X12 EDI, it is a data format used to encode
common business documents like purchase orders, delivery notices, and health
care claims. It is similar to XML in some ways, but precedes it by about 15
years; so if you think XML sucks, you will love to hate EDI.

## Scope and licensing

**Tediparse ships the engine, not the grammars.** The library does not bundle
any X12 transaction-set definitions, code lists, envelopes, or ack/editor
content — that material is X12 IP and is not ours to redistribute. To parse
or generate real X12 documents you must supply (or license) your own grammar
and register it against `Stupidedi::Config` before calling the parser.

If you reach for one of the per-era namespaces that the upstream `stupidedi`
gem shipped — `Stupidedi::Versions::FiftyTen`, `Stupidedi::TransactionSets::FortyTen`,
`Stupidedi::Interchanges::FiveOhOne`, and so on — tediparse raises a typed
`Stupidedi::Exceptions::MissingGrammarError` with guidance, rather than
`NameError`. Parser-driven lookups against an empty config produce a
`FailureState` whose reason carries the same message.

**Engine scope.** Tediparse provides parsing and generation as a library. The
upstream gem's editor / acknowledgement subsystem (TA1 / 999 / 277CA) and
the `bin/edi-pp` / `edi-ed` / `edi-obfuscate` command-line tools are not
part of tediparse.

### Authoring a grammar

The canonical reference for how to wire up your own grammar against the
engine lives in the spec harness:

- `spec/support/synthetic/demo.rb` — a small adversarial transaction set
  built with `Stupidedi::TransactionSets::Builder`. Exercises composites,
  code lists, interleaved segments and child loops, qualifier-discriminated
  sibling loops, and the `P` syntax note.
- `spec/support/synthetic/interchange_def.rb` — minimal ISA envelope.
- `spec/support/synthetic/functional_group_def.rb` — minimal GS envelope.
- `spec/support/synthetic/config.rb` — wires the three pieces into a usable
  `Stupidedi::Config`.

Mirror that shape in your own application and register against
`Stupidedi::Config.new` (the legacy `Config.default` / `hipaa` / `contrib`
factories are preserved for source compatibility but now return empty
configs).

### Generating a grammar from ASC X12 Table Data

Hand-authoring is fine for a handful of segments, but a full transaction set
is hundreds of definitions. With an **ASC X12 license** you can download the
**Table Data** (the official `.TXT` distribution — `ELEHEAD`, `SEGDETL`,
`SETDETL`, `FREEFORM`, etc.) from <https://ecommerce.x12.org/downloads>, and
tediparse can generate the grammar definition files for you. The full
walkthrough — input file formats, the output tree, loading, multi-release
trees, and how it works — is in
[doc/Generating-Grammars.md](doc/Generating-Grammars.md); the short version:

```sh
tediparse generate --release 005010 \
  --table-data vendor/x12/table_data/005010 \
  --out lib
```

or from Ruby:

```ruby
Stupidedi::Schema::Generation.run(
  table_data: "vendor/x12/table_data/005010",
  release:    "005010",
  out:        "lib",
  namespace:  "Edi" # root module for the emitted code (default: "Edi")
)
```

This reads the flat files and writes a grammar tree under `<out>/<namespace>/`
— per-version support modules, `element_defs.rb`, `segment_defs.rb`,
`functional_group_def.rb`, one file per transaction set under `standards/`, an
interchange envelope under `interchanges/`, and a `stupidedi_registration.rb`
that wires everything onto a `Config`. Use `--dry-run` to preview without
writing. Supported releases: `004010`, `004060`, `005010`, `006010`, `007010`,
`008010`.

You can keep several releases in one output tree. Generating an additional
release preserves the ones already present: `stupidedi_registration.rb` (and the
master loader, if any) are whole-tree artifacts that are rebuilt to cover every
release in `out`, not just the one you just generated. To rebuild those
aggregation files on their own — e.g. after adding or removing a release by other
means — run `tediparse register --out DIR` (or `Stupidedi::Schema::Generation.register(out:)`).

By default the generated tree is loaded by your application's autoloader (e.g.
Rails/Zeitwerk). If you are not using an autoloader, pass `--master-loader`
(or `master_loader: true`) to also emit a single entry file (`<namespace>.rb`,
e.g. `edi.rb`) that `require`s the whole tree in dependency order, so
`require "edi"` is all you need.

The X12 Table Data you supply is licensed X12 IP, and the generated grammar is
a derivative you own — **neither ships with this gem.** The generator is the
machine; you bring the material. The committed fixture under
`spec/support/generation/table_data/` is a hand-written synthetic grammar in
the same flat-file format, not real X12 content.

### Conformance suite

If you have private grammars and need to keep them tested against tediparse,
the upstream X12 fixture corpus and grammar tree remain recoverable from the
pre-removal commit:

    git fetch --tags
    git worktree add ../conformance pre-x12-removal

Build the conformance suite against that worktree's fixtures, layer your
licensed grammar on top, and run it out-of-tree.

## Attribution

This product includes software from `stupidedi` by Kyle Putnam, available at
<https://github.com/kputnam/stupidedi>.

### Fork relationship

Tediparse is a fork of [stupidedi](https://github.com/kputnam/stupidedi),
maintained by [Adrian Duyzer](https://github.com/adriand) at
[Tediware](https://github.com/Tediware). The fork was created to accelerate
development and support a broader set of X12 documents. The internal Ruby
module name remains `Stupidedi` for backward compatibility; `require "tediparse"` and `require "stupidedi"` both work.

### Credits

- **Original author**: [Kyle Putnam](https://github.com/kputnam)
- **Tediparse maintainer**: [Adrian Duyzer](https://github.com/adriand)

## What problem does it solve?

Transaction set specifications can be enormous, boring, and vague. Trading
partners can demand strict adherence (often to their own unique
interpretation of the specification) of the documents you generate. However,
documents they generate themselves are often non-standard and require
flexibility to parse them.

Tediparse enables you to encode these transaction set specifications directly
in Ruby. From these specifications, it will generate a parser to read
incoming messages and a DSL to generate outgoing messages. This approach has
a huge advantage over writing a parser from scratch, which can be error-prone
and difficult to change.

### Robust tokenization and parsing

Delimiters, line breaks, and out-of-band data between interchanges are
handled correctly. While many trading partners follow common conventions, it
only takes one unexpected deviation, like swapping the ":" and "~"
delimiters, to render a hand-written parser broken.

Tediparse handles many edge cases that can only be anticipated by reading
carefully between the lines of the X12 documentation.

### Instant feedback on error conditions

When generating EDI documents, validation is performed incrementally on each
segment. This means the instant your client code violates the specification,
an exception is thrown with a meaningful stack trace. Other libraries only
perform validation after the entire document has been generated, while some
don't perform validation at all.

### Encourages readable client code

Unlike other libraries, generating documents doesn't involve naming obscure
identifiers from the specification (like C001, DE522 or LOOP2000), for
elements of the grammar that don't actually appear in the output.

Like HAML or Builder::XmlMarkup, the DSL for generating documents closely
matches terminology from the problem domain. You can see in the example
below that code looks very similar to an EDI document.

### Efficient parsing and traversing

The parser is designed using immutable data structures, making it thread-safe
for runtimes that can utilize multiple cores. In some cases, immutability
places higher demand on garbage collection; this has been somewhat mitigated
with careful optimization.

## Examples

The examples below assume `config` is a `Stupidedi::Config` you've populated
with your own grammar — see `spec/support/synthetic/config.rb` for the
authoring pattern.

### Generating, Writing

#### X12 Writer

```ruby
require "tediparse"

# You bring the grammar. See spec/support/synthetic for the authoring shape.
config = MyApp::EDI.config

b = Stupidedi::Parser::BuilderDsl.build(config)

# These methods perform error checking: number of elements, element types, min/max
# length requirements, conditionally required elements, valid segments, number of
# segment occurrences, number of loop occurrences, etc.
b.ISA "00", nil, "00", nil,
      "ZZ", "SUBMITTER ID",
      "ZZ", "RECEIVER ID",
      "990531", "1230", nil, "00501", "123456789", "1", "T", nil

# The API tracks the current position in the specification (e.g., the current loop,
# table, etc) to ensure well-formedness as each segment is generated.
b.GS "HC", "SENDER ID", "RECEIVER ID", "19990531", "1230", "1", "X", "005010X222"

b.ST "837", "1234", b.default
  b.BHT "0019", "00", "X"*30, "19990531", Time.now.utc, "CH"
  b.NM1 b.default, "1", "PREMIER BILLING SERVICE", nil, nil, nil, nil, "46", "12EEER000TY"
  # ...

b.machine.zipper.tap do |z|
  separators =
    Stupidedi::Reader::Separators.build :segment    => "~\n",
                                        :element    => "*",
                                        :component  => ":",
                                        :repetition => "^"

  w = Stupidedi::Writer::Default.new(z.root, separators)
  print w.write()
end
```

#### HTML writer

`Stupidedi::Writer::Default` outputs plain X12; `Stupidedi::Writer::Claredi`
outputs a formatted HTML string.

```ruby
b.machine.zipper.tap do |z|
  w = Stupidedi::Writer::Claredi.new(z.root)
  File.open('output.html', 'w') { |f| f.write w.write }
end
```

### Reading, Traversing

```ruby
require "tediparse"

config = MyApp::EDI.config
parser = Stupidedi::Parser.build(config)

input  = File.open("path/to/your.edi", :encoding => "ISO-8859-1")

# Reader.build accepts IO (File), String, and DelegateInput
parser, result = parser.read(Stupidedi::Reader.build(input))

# Report fatal tokenizer failures
if result.fatal?
  result.explain{|reason| raise reason + " at #{result.position.inspect}" }
end

# Helper function: fetch an element from the current segment
def el(m, *ns, &block)
  if Stupidedi::Either === m
    m.tap{|m| el(m, *ns, &block) }
  else
    yield(*ns.map{|n| m.elementn(n).map(&:value).fetch })
  end
end

parser.first
  .flatmap{|m| m.find(:GS) }
  .flatmap{|m| m.find(:ST) }
  .tap do |m|
    el(m.find(:N1, "PR"), 2){|e| puts "Payer: #{e}" }
    el(m.find(:N1, "PE"), 2){|e| puts "Payee: #{e}" }
  end
  .flatmap{|m| m.find(:LX) }
  .flatmap{|m| m.find(:CLP) }
  .flatmap{|m| m.find(:NM1, "QC") }
  .tap{|m| el(m, 3, 4){|l,f| puts "Patient: #{l}, #{f}" }}
```

### Testing

```
bundle exec rake spec
```

## What doesn't it solve?

It isn't a translator. It doesn't have bells and whistles, like the
commercial EDI translators have, so it...

- Doesn't convert to/from XML, CSV, etc
- Doesn't transmit or receive files
- Doesn't do encryption
- Doesn't connect to your database
- Doesn't queue messages for delivery or receipt
- Doesn't generate acknowledgements
- Doesn't have a graphical interface

These features are orthogonal to the problem tediparse aims to solve, but
they can certainly be implemented with other code taking advantage of
tediparse.
