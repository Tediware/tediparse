v Unreleased

  Tediparse is now a maintained fork of `stupidedi` (Kyle Putnam, upstream
  maintained by Isi Robayna). The internal `Stupidedi` module name is
  preserved for source compatibility — `require "tediparse"` and `require
  "stupidedi"` both work.

  **Breaking: X12 grammar content removed**

  Tediparse ships the engine, not the grammars. Roughly 856 files of X12
  IP have been removed from `lib/`: every per-era version namespace
  (`Versions::TwoThousandOne` through `FiftyTen`), every transaction-set
  definition (standards and HIPAA implementations under
  `transaction_sets/<version>/`), every interchange envelope
  (`interchanges/{00200,00300,00400,00401,00501}/`), and the
  `editor/` / `contrib/` / `guides/` trees.

  Before relying on tediparse you must register your own grammar against
  `Stupidedi::Config`. See `spec/support/synthetic/` in the source tree
  for a worked authoring example.

  * **Recovering the upstream corpus.** The full content tree and the
    ~146 `.edi` fixtures live at the `pre-x12-removal` git tag. Use
    `git worktree add ../conformance pre-x12-removal` to drive a private
    conformance suite against the engine while keeping X12 IP out of
    the published gem.
  * `Validation::Ambiguity.build` now requires an `InterchangeDef` as
    a third positional argument — pass your synthetic envelope (see
    `spec/support/synthetic/interchange_def.rb`). The previous
    nil-default would crash inside `mkconfig` when the validator
    actually ran.

  **Helpful failure surface**

  * Add `Stupidedi::Exceptions::MissingGrammarError` (subclass of
    `StupidediError`). Const lookups against the removed namespaces —
    `Stupidedi::Editor`, `Stupidedi::Contrib`, `Stupidedi::Guides`,
    the per-era `Stupidedi::Versions::FiftyTen` /
    `Stupidedi::TransactionSets::FortyTen` /
    `Stupidedi::Interchanges::FiveOhOne` style references, plus the
    long-deprecated `Versions::FunctionalGroups` /
    `Versions::Interchanges` aliases — raise it with a message that
    names the requested constant and points users at the authoring
    reference. Legitimate typos still surface as `NameError`.
  * Parser-driven lookups against an empty config now push a
    `FailureState` whose reason is the same helpful message instead of
    the generic "unknown … version" string. Applies to all three
    parser states (`InterchangeState`, `FunctionalGroupState`,
    `TransactionSetState`).
  * `Config::InterchangeConfig`, `FunctionalGroupConfig`, and
    `TransactionSetConfig` gain an `empty?` predicate.
  * `InterchangeConfig#register`, `FunctionalGroupConfig#register`, and
    `TransactionSetConfig#register` now raise `ArgumentError` when
    called with neither a definition nor a block, instead of silently
    storing `nil` under the key. Catches the `register("DEMO01")` typo
    that would otherwise produce a confusing `NoMethodError` deep in
    the parser.

  **Removed**

  * `bin/edi-pp`, `bin/edi-ed`, `bin/edi-obfuscate` — the gem no longer
    ships executables.
  * `lib/stupidedi/editor/` and `editor.rb` (the entire TA1 / 999 /
    277CA acknowledgement subsystem).
  * `lib/stupidedi/contrib/`, `contrib.rb`, `guides.rb`.
  * Per-era autoloads from `lib/stupidedi.rb`, `interchanges.rb`,
    `versions.rb`, `transaction_sets.rb`.
  * `Config.default` / `Config.hipaa` / `Config.contrib` factory bodies
    — the methods are preserved as documented no-ops returning a fresh
    empty `Config`, for source compatibility.
  * `Stupidedi::Config::EditorConfig` and the `Config#editor` reader —
    the editor registry only had callers inside the now-deleted
    `lib/stupidedi/editor/` tree.
  * Top-level `notes/` scratch directory — historical maintainer
    examples (X12 generator, recovery script, JSON writer demo) that
    all referenced the deleted X12 grammar tree. Still recoverable
    from the `pre-x12-removal` tag.
  * Top-level `examples/` directory (`generate.rb`, `tokenizer.rb`) —
    both scripts were hard-wired to `Config.hipaa` and crashed at
    runtime against the now-empty config. `spec/support/synthetic/` is
    the canonical worked example; the old scripts are still recoverable
    from the `pre-x12-removal` tag.

  **Added**

  * `spec/support/synthetic/` — a small non-X12 grammar harness
    (interchange + functional group + transaction set + adversarial
    variants) used to exercise the engine in tests. Doubles as the
    canonical grammar-authoring reference.

  **Bug fixes**

  * `Schema::Generation::FlatFileReader` declared the wrong encoding for
    every supported release. It read the ASC X12 Table Data as ISO-8859-1;
    004060 through 007010 are Windows-1252 (so CP1252 smart punctuation at
    0x80-0x9F decoded to C1 control characters) and 008010 is UTF-8 (so
    every multi-byte character was double-encoded). Both transcoded
    silently, and the damage reached the generated grammar. The encoding is
    now declared per release in `FlatFileReader::SOURCE_ENCODINGS`; an
    undeclared release is read as UTF-8, deliberately, so a wrong assumption
    raises instead of writing mojibake. Decoded text has CP1252 smart
    quotes and dashes normalized to ASCII (accented letters are left
    alone), and a C1 control character surviving the decode raises with the
    file, line and codepoint. **Consumers should regenerate their grammar
    tree**: affected element and segment names change.

  **Bug fixes** (carried over from prior fork work)

  * Fix `too much non-determinism` error when a `LoopDef` contains repeated
    structurally-identical `SegmentUse` slots (same id, no qualifier element)
    and only the earlier slot is filled — e.g. an N3 in the partner-customised
    4010 PO850 N1 loop. `ConstraintTable::ValueBased` now consults the active
    parser state's parse tree to pick the slot whose preceding sibling has
    actually been consumed: the earliest position past the highest-consumed
    sibling in the matching parent loop. This requires plumbing the active
    `AbstractState` through `InstructionTable#matches` and the `ConstraintTable`
    subclasses' `matches`. Behaviour is unchanged for qualifier-disambiguated
    paths (e.g. N1 by N101) and for genuinely ambiguous cases across different
    parent loops. During `find` navigation the `mode == :insert` gate skips
    disambiguation entirely, so the full candidate set is preserved.
  * Build out 5010 SO317 as a test case for interleaved segments and child
    loops within a single `LoopDef`.

v 1.4.1

  **Bug Fixes**

  * Fix missing method delegations in SimpleElementUse, ComponentElementUse, and CompositeElementUse #185
  * Fix regression in edi-obfuscate
  * Fix copy-pasted StringVal -> IdentifierVal #187
  * Fix crash in 4010 editor, wrong method called #188
  * Fix bug in RepeatedElementVal#==, incorrect comparison #190
  * Fix error message when required composite element is missing #194
  * Fix various typos in comments and descriptor strings #230 and #233

  **Added**

  * Add DSL for defining X12 grammars TransactionSets::Builder::Dsl #200
  * Add support for 5010 X12-HN277 Health Care Information Status Notification
  * Add support for 5010 X220A1-BE834 BGN05 Time Code #205
  * Add support for "02 - Birth" maintenance reason code #209

v 1.4.0

  **Bug fixes**

  * Fix ambiguous grammars (mostly due to incorrect parentheses)
  * Fix errors in `Standards::FortyTen::HC837`
  * Fix errors in `Standards::FiftyTen::BE834`
  * Fix errors in `Standards::FiftyTen::HB271`
  * Fix errors in `Standards::FiftyTen::RA820`
  * Fix parsing invalid numeric data in Ruby 2.4+. Previously `"10B"` would be read as `10.0`, and `"AB10"` would be read as `0.0` due to using bigdecimal/util's implementation of `String#to_d`
  * Fix `TimeVal` issue in all versions (not only `005010`)

  **Added**

  * Add `Stupidedi::Parser.build` as a shortcut for `Stupidedi::Parser::StateMachine.build`
  * Add many stub definitions of segments, just the segment name and no elements, which are referred to by `RA820` and others.
  * `edi-pp` can now print different formats with `--format html`, `--format x12`, and `--format tree` (default)

  **Deprecation notices**

  * Remove support for Ruby < 2.0
  * Remove workarounds for broken JRuby refinements
  * Remove `Symbol#call` and `Symbol#to_proc` refinements

  **Renamed**

  * `Stupidedi::Builder` is renamed to `Stupidedi::Parser`
  * `Stupidedi::Guides::*::GuideBuilder` is renamed to `Stupidedi::TransactionSets::Builder`
  * `Stupidedi::Versions::Interchanges` is renamed to `Stupidedi::Interchanges`
  * `Stupidedi::Versions::FunctionalGroups` is renamed to `Stupidedi::Versions`
    * Lots of common code among versions has been factored into `Stupidedi::Versions::Common`
  * Rename Guides `HC837P` and `HC837I` to `HC837`
  * Moved all grammars, including `Guides` and `Contrib`, to `Stupidedi::TransactionSets`
    * Each version now has `::Standards` and `::Implementations`
  * `Stupidedi::Schema::Auditor` is renamed to `Stupidedi::TransactionSets::Validation::Ambiguity`

  Most of these renames are not breaking changes (yet), but using the old name will print a warning:

  ```
  Stupidedi::Contrib is deprecated, use Stupidedi::TransactionSets
  Stupidedi::Guides is deprecated, use Stupidedi::TransactionSets::*::Implementations
  Stupidedi::TransactionSets::FiftyTen::Implementations::X222::HC837P is deprecated, use HC837 instead
  Stupidedi::TransactionSets::FiftyTen::Implementations::X222A1::HC837P is deprecated, use HC837 instead
  Stupidedi::TransactionSets::FiftyTen::Implementations::X223::HC837I is deprecated, use HC837 instead
  Stupidedi::Versions::Interchanges is deprecated, use Stupidedi::Interchanges instead
  Stupidedi::Versions::FunctionalGroups is deprecated, use Stupidedi::TransactionSets::*::Standards instead
  ```

  **Specs**

  * Grammar specs automatically created when a fixture is added to spec/fixtures/<version>/<name>/pass/*.x12
  * Remove support for `rcov`. Use only `simplecov` now
  * Update all specs to use `expect(value).to matcher` syntax, instead of `value.should matcher`
  * New specs to ensure element names match their `id` (eg, `E123.id == :E123`)
  * New specs to ensure segment names match their `id` (eg `ST.id == :ST`)
  * New specs to ensure `Config.hipaa`, `Config.contrib`, and `Config.default` reference valid definitions
  * New specs for `Stupidedi::TransactionSets::Validation::Ambiguity`
  * Fix fixture files that used `\n` as a segment terminator but didn't have one after `IEA`

  **Miscellaneous**

  * Create new examples in `examples/` that demonstrate undocumented `IdentifierStack`, and more
  * Made whitespace and other formatting more consistent
  * `Stupidedi::TransactionSets::Builder.build` no longer requires a `TransactionSetDef` argument
  * Fix Travis CI to build older versions of Ruby < 2.3
  * Ignore large definition files in Code Climate

v 1.3.24
  - Fix repeatability test in Navigation#iterate
  - Adds implementation of June 2014 005010X223A3 (837I)
  - Fixes misplaced 2330H and 2330I loops. Fixes names for 2310 Occurrenc…

v 1.3.23 - Jan 10, 2019
  - Fix decimal values for TimeVal being coerced incorrectly https://github.com/irobayna/stupidedi/pull/151
  - Detect ambiguous grammar automatically https://github.com/irobayna/stupidedi/pull/153

v 1.3.22
  - Re-enable EC Segment on FifyTen group

v 1.3.21 - Dec 9, 2018 ** Breaking Changes **
  - Throw exception from #iterate if segment is not repeatable (fix #126) https://github.com/irobayna/stupidedi/pull/146
  - Configurable limit of non-determinism (fixes #129) https://github.com/irobayna/stupidedi/pull/145
  - Add utility to obfuscate data in X12 files https://github.com/irobayna/stupidedi/pull/147
  - Fix potential frozen string issues in pretty_print methods https://github.com/irobayna/stupidedi/pull/148
  - Remove erroneous code mappings from element definitions

v 1.2.20 - Oct 23, 2018
  - Json Writer functionality - Traverse stupidedit internal tree to a ruby hash
  - Ruby 2.5.3 support

v 1.2.19 - Oct 8, 2018
  - EDI 276 support - Health Care Claim Status Inquiry
    X212-HR276

v 1.2.18 -
  - SH856 rework
  - PR855 support (v4010)
  - This change fixes this issue, as if decimal is an empty string, it will be changed to 0 before to_d is called on it
    https://github.com/irobayna/stupidedi/pull/132
    Update  lib/stupidedi/versions/functional_groups/004010/element_types/time_val.rb


v 1.2.17 - Aug 4, 2018
  - EDI 270 / 271 support - Health Care Eligibility Benefit Inquiry and Response
    X279-HS270
    X279-HB271
    X279A1-HS270
    X279A1-HB271

v 1.2.16 - May 27, 2018
  - Fix item #127 (https://github.com/irobayna/stupidedi/issues/127)
  - Ruby 2.5.1 support

v 1.2.15 - Dec 20, 2017
  - Gemfile Updates (fix security vulnerability CVE-2017-17042)
  - Add Ruby 2.5.0-preview1 support
  - Add 2.4.3 & 2.5.0-preview1 ruby versions to Travis CI

v 1.2.14 - June 19, 2017
  - Gemfile Updates
  - use BigDecimal string refinement only on ruby versions < 2.4
  - remove rake from gemspec
  - Add Ruby 2.4.x support

v 1.2.12 - July 29, 2016
  - Fix a few issues with immutable strings

v 1.2.2 - July 8, 2014
  - Remove definition of module Enumerable::blank? and present?
  - Add blank?, present? to Array class

v 1.2.1 - July 7, 2014
  - Don't redefine 'blank?' for Enumerable, if an implementation already (rails support)

v 1.2.0 - July 7, 2014
  - Don't redefine try, if active_support provides an implementation already (better rails support)

v 1.1.0 - June 24, 2014
  - Rspec 3.x support
  - Drop Ruby 1.8.7 support
  - Add Ruby 2.1.2 support
