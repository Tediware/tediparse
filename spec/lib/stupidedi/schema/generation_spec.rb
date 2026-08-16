# frozen_string_literal: true

require "spec_helper"
require "tmpdir"
require "shellwords"
require "fileutils"

describe Stupidedi::Schema::Generation do
  Generation = Stupidedi::Schema::Generation

  # Committed synthetic ASC X12 Table Data fixture (see spec/support/generation).
  # The gem ships no real X12 content; this is a hand-written, minimal grammar.
  fixture_dir = File.expand_path("../../../support/generation/table_data/005010", __dir__)

  describe "FlatFileReader" do
    subject(:release) { Generation::FlatFileReader.read(fixture_dir, "005010") }

    it "reads elements, segments and transaction sets" do
      expect(release.code).to eq("005010")
      expect(release.elements.size).to eq(31)   # 30 simple + 1 composite
      expect(release.segments.size).to eq(9)
      expect(release.transaction_sets.map(&:code)).to contain_exactly("204", "997", "123")
    end

    it "reads a transaction set with no functional group as nil func_group" do
      ts997 = release.transaction_sets.find { |t| t.code == "997" }
      expect(ts997.func_group).to be_nil # blank func_group column -> nil
    end

    it "maps requirement designators (M/O/C/N -> Mandatory/Optional/Conditional/NotUsed)" do
      bgn = release.segments.find { |s| s.code == "BGN" }
      reqs = bgn.element_uses.sort_by(&:position).map(&:requirement)
      expect(reqs).to eq(%w[Mandatory Optional Optional])
    end

    it "reads the SEGDETL repetition count into the element use (default 1)" do
      ref = release.segments.find { |s| s.code == "REF" }
      uses = ref.element_uses.sort_by(&:position)
      expect(uses.map(&:max_reps)).to eq([1, 5]) # 127 once, 353 up to five times
    end

    it "treats type-less elements (separators) as control elements" do
      i65 = release.elements.find { |e| e.code == "I65" }
      i15 = release.elements.find { |e| e.code == "I15" }
      expect(i65.x12_type).to be_nil
      expect(i15.x12_type).to be_nil
    end

    it "parses composites and their component uses" do
      c001 = release.elements.find { |e| e.code == "C001" }
      expect(c001.is_composite).to be(true)
      expect(c001.component_uses.sort_by(&:position).map { |cu| [cu.element.code, cu.requirement] })
        .to eq([["127", "Mandatory"], ["353", "Optional"]])
    end

    it "extracts ID code lists from FREEFORM" do
      e353 = release.elements.find { |e| e.code == "353" }
      expect(e353.element_codes.map { |c| [c.code, c.name] })
        .to contain_exactly(["00", "Original"], ["01", "Cancellation"])
    end

    it "flushes the final FREEFORM block at EOF (the upstream importer drops it)" do
      # BGN's P0203 syntax note is the last block in FREEFORM.TXT.
      bgn = release.segments.find { |s| s.code == "BGN" }
      expect(bgn.syntax_notes.map { |n| [n.condition_type, n.element_positions] })
        .to eq([["paired", [2, 3]]])
    end

    it "reconstructs the table/loop tree with unbounded vs bounded repeats" do
      ts = release.transaction_sets.find { |t| t.code == "204" }
      expect(ts.func_group).to eq("SM")
      expect(ts.table_definitions.map(&:area)).to eq(%w[heading detail summary])

      detail = ts.table_definitions.find { |t| t.area == "detail" }
      loop = detail.ordered_children.first
      expect(loop.segment_use?).to be(false)
      expect(loop.identifier).to eq("N1")
      expect(loop.max_reps).to be_nil # ">1" -> unbounded
      expect(loop.ordered_children.map { |c| c.segment.code }).to eq(["REF"])
    end

    it "wires each transaction set back to its release" do
      expect(release.transaction_sets.first.release).to be(release)
    end

    # X12 loop IDs are only unique within their nesting context. The "123" set
    # carries the collision shape from the real 004010 850 (heading N1 loop vs
    # the N1 loop nested under SPI): a level-1 REF loop, then a level-2 REF
    # loop nested under a TA1 loop, each with its own repeat count.
    describe "same-ID loops at different nesting positions" do
      let(:ts)         { release.transaction_sets.find { |t| t.code == "123" } }
      let(:detail)     { ts.table_definitions.find { |t| t.area == "detail" } }
      let(:outer_ref)  { detail.ordered_children[0] }
      let(:ta1)        { detail.ordered_children[1] }
      let(:nested_ref) { ta1.ordered_children.find { |c| !c.segment_use? } }

      it "creates a distinct LoopDefinition per opening row" do
        expect(outer_ref.identifier).to eq("REF")
        expect(ta1.identifier).to eq("TA1")
        expect(ta1.ordered_children.reject(&:segment_use?).map(&:identifier)).to eq(["REF"])
        expect(nested_ref).not_to be(outer_ref)
      end

      it "keeps the outer loop's children free of the nested loop's rows" do
        expect(outer_ref.ordered_children.map { |c| [c.segment.code, c.position] })
          .to eq([["REF", 100], ["BGN", 200]])
      end

      it "preserves the nested loop's own repeat count" do
        expect(outer_ref.max_reps).to eq(200)
        expect(nested_ref.max_reps).to eq(20)
        expect(nested_ref.ordered_children.map { |c| c.segment.code }).to eq(%w[REF BGN])
      end

      it "drops no segment row" do
        flatten = lambda do |node|
          node.children.flat_map { |c| c.segment_use? ? [c] : flatten.call(c) }
        end
        segment_uses = ts.table_definitions.flat_map { |t| flatten.call(t) }
        expect(segment_uses.size).to eq(8) # one per SETDETL row for "123"
      end
    end
  end

  # The distribution occasionally ships a column-shifted SETDETL row: a value
  # lands one field left of where it belongs. What the reader makes of it is
  # either a loop or segment that may occur zero times — RepeatCount.bounded(0)
  # raises, so the emitted grammar dies when the consumer loads it, naming
  # nothing — or a loop identified as "0", which builds and loads fine and
  # quietly reparents the rest of the table. Reject the row here instead, where
  # it can still be pointed at.
  describe "defective structure rows" do
    # Copy the committed fixture, replacing one SETDETL row.
    def corrupt_setdetl(source_dir, from, to)
      Dir.mktmpdir do |tmp|
        dir = File.join(tmp, "table_data")
        FileUtils.cp_r(source_dir, dir)

        path = File.join(dir, "SETDETL.TXT")
        rows = File.read(path)
        raise "fixture row not found: #{from}" unless rows.include?(from)

        File.write(path, rows.sub(from, to))
        yield dir
      end
    end

    it "rejects a loop whose repeat count shifted out of its column" do
      corrupt_setdetl(fixture_dir,
                      '"123","2","0100","REF","O","1","1","200","REF"',
                      '"123","2","0100","REF","O","1","1","","REF"') do |dir|
        expect { Generation::FlatFileReader.read(dir, "005010") }
          .to raise_error(ArgumentError,
                          /SETDETL\.TXT: transaction set 123, area 2, sequence 0100 \(REF\): loop repeat "" parses to a repeat count of 0/)
      end
    end

    it 'rejects "0" as a loop identifier' do
      corrupt_setdetl(fixture_dir,
                      '"123","2","0100","REF","O","1","1","200","REF"',
                      '"123","2","0100","REF","O","1","1","200","0"') do |dir|
        expect { Generation::FlatFileReader.read(dir, "005010") }
          .to raise_error(ArgumentError, /sequence 0100 \(REF\): "0" is not a loop identifier/)
      end
    end

    it "rejects a segment use whose maximum use is blank" do
      corrupt_setdetl(fixture_dir,
                      '"204","1","0200","BGN","M","1","0","0",""',
                      '"204","1","0200","BGN","M","","0","0",""') do |dir|
        expect { Generation::FlatFileReader.read(dir, "005010") }
          .to raise_error(ArgumentError,
                          /transaction set 204, area 1, sequence 0200 \(BGN\): maximum use "" parses to a repeat count of 0/)
      end
    end

    it "leaves an unbounded maximum use alone" do
      corrupt_setdetl(fixture_dir,
                      '"204","1","0200","BGN","M","1","0","0",""',
                      '"204","1","0200","BGN","M",">1","0","0",""') do |dir|
        release = Generation::FlatFileReader.read(dir, "005010")
        heading = release.transaction_sets.find { |t| t.code == "204" }
                         .table_definitions.find { |t| t.area == "heading" }
        bgn = heading.ordered_children.find { |c| c.segment.code == "BGN" }
        expect(bgn.max_reps).to be_nil
      end
    end
  end

  # The .TXT distribution is Windows-1252 through 007010 and UTF-8 from 008010.
  # Reading it as ISO-8859-1 (the obvious guess, and what this reader used to do)
  # transcodes silently: accented letters survive, but CP1252 smart punctuation
  # at 0x80-0x9F becomes a C1 control character in the generated grammar.
  describe "source encoding" do
    # A minimal table-data directory: one element, plus optional FREEFORM.
    def table_data(dir, elehead, freeform = nil)
      FileUtils.mkdir_p(dir)
      File.binwrite(File.join(dir, "ELEHEAD.TXT"), elehead)
      File.binwrite(File.join(dir, "ELEDETL.TXT"), "127,AN,1,30\r\n")
      File.binwrite(File.join(dir, "FREEFORM.TXT"), freeform) if freeform
      dir
    end

    def element_name(dir, release_code)
      Generation::FlatFileReader.read(dir, release_code).elements.first.name
    end

    it "declares an encoding for every supported release" do
      expect(Generation::FlatFileReader::SOURCE_ENCODINGS.keys)
        .to match_array(Generation::VERSION_MODULES.keys)
    end

    it "decodes Windows-1252 punctuation and normalizes it to ASCII" do
      Dir.mktmpdir do |tmp|
        # 0x92 right single quote, 0x96 en dash - C1 controls read as Latin-1.
        dir = table_data(tmp, "127,Shipper\x92s Reference \x96 Number\r\n")
        expect(element_name(dir, "005010")).to eq("Shipper's Reference - Number")
      end
    end

    it "normalizes punctuation in FREEFORM code names too" do
      Dir.mktmpdir do |tmp|
        dir = table_data(tmp, "127,Reference Identification\r\n",
                         "*ELECOD\r\n127, ,00,1\r\nShipper\x92s Original\r\n")
        element = Generation::FlatFileReader.read(dir, "007010").elements.first
        expect(element.element_codes.map(&:name)).to eq(["Shipper's Original"])
      end
    end

    it "does not transliterate accented letters" do
      Dir.mktmpdir do |tmp|
        dir = table_data(tmp, "127,Fianc\xE9e Denominaci\xF3n M\xE4rzen\r\n")
        expect(element_name(dir, "007010")).to eq("Fiancée Denominación Märzen")
      end
    end

    it "reads 008010 as UTF-8 rather than double-encoding it" do
      Dir.mktmpdir do |tmp|
        dir = table_data(tmp, "127,Fianc\xC3\xA9e\r\n") # e-acute, already UTF-8
        expect(element_name(dir, "008010")).to eq("Fiancée")
      end
    end

    # An undeclared release must default to UTF-8, not to a single-byte
    # encoding: single-byte encodings decode every byte, so a wrong guess can
    # only fail silently.
    it "fails on an undeclared release whose data is not UTF-8" do
      Dir.mktmpdir do |tmp|
        dir = table_data(tmp, "127,Shipper\x92s Reference\r\n")
        expect { Generation::FlatFileReader.read(dir, "009010") }
          .to raise_error(ArgumentError, /Could not decode.*as UTF-8.*009010.*SOURCE_ENCODINGS/m)
      end
    end

    it "rejects a C1 control character, naming the file, line and codepoint" do
      Dir.mktmpdir do |tmp|
        # Valid UTF-8 that decodes to U+0092 - i.e. data already damaged upstream.
        dir = table_data(tmp, "127,First\r\n128,Shipper\xC2\x92s Reference\r\n")
        expect { Generation::FlatFileReader.read(dir, "008010") }
          .to raise_error(ArgumentError, /U\+0092 at .*ELEHEAD\.TXT line 2/)
      end
    end

    it "reports a byte that is undefined in the declared encoding" do
      Dir.mktmpdir do |tmp|
        dir = table_data(tmp, "127,Bad\x81Name\r\n") # 0x81 is undefined in CP1252
        expect { Generation::FlatFileReader.read(dir, "005010") }
          .to raise_error(ArgumentError, /Could not decode.*as Windows-1252/m)
      end
    end

    it "ignores a UTF-8 BOM instead of folding it into the first key" do
      Dir.mktmpdir do |tmp|
        dir = table_data(tmp, "\xEF\xBB\xBF127,Reference Identification\r\n")
        element = Generation::FlatFileReader.read(dir, "008010").elements.first
        expect(element.code).to eq("127")
        expect(element.name).to eq("Reference Identification")
      end
    end
  end

  describe "generators" do
    let(:release) { Generation::FlatFileReader.read(fixture_dir, "005010") }

    it "emits simple, numeric, ID-with-codelist, composite and separator elements" do
      out = Generation::ElementGenerator.new(release).generate
      expect(out).to include('E127 ||= t::AN.new(:E127, "Reference Identification", 1, 30)')
      expect(out).to include('E96 ||= t::Nn.new(:E96, "Number of Included Segments", 1, 10, 0)')
      expect(out).to include('E353 ||= t::ID.new(:E353, "Transaction Set Purpose Code", 2, 2,')
      expect(out).to include('s::CodeList.build(')
      expect(out).to include("C001 ||= s::CompositeElementDef.build(:C001,")
      expect(out).to include("EI65 ||= Stupidedi::Interchanges::ElementTypes::Separator.new(:EI65,")
    end

    it "emits control segments only when requested" do
      without = Generation::SegmentGenerator.new(release).generate
      with = Generation::SegmentGenerator.new(release, include_control_segments: true).generate
      expect(without).not_to include("ISA ||= s::SegmentDef.build(:ISA,")
      expect(with).to include("ISA ||= s::SegmentDef.build(:ISA,")
      # composite element use carries no E prefix
      expect(with).to include("e::C001.simple_use(")
      # syntax note from the EOF-flushed block
      expect(with).to include("SyntaxNotes::P.build(2, 3)")
      # element repeat count from SEGDETL: REF's 353 repeats up to 5 times,
      # while a non-repeating use stays bounded(1).
      expect(with).to include("e::E353.simple_use(r::Optional, s::RepeatCount.bounded(5))")
      expect(with).to include("e::E127.simple_use(r::Mandatory, s::RepeatCount.bounded(1))")
    end

    it "maps higher-precision Nn types (N3/N5/N7/N8/N9) the engine supports" do
      rel = Generation::Models::Release.new(
        code: "005010",
        elements: [Generation::Models::Element.new(
          code: "9999", name: "Synthetic Decimal", description: nil,
          x12_type: "N3", is_composite: false, min_length: 1, max_length: 9,
          digits: 3, element_codes: [], component_uses: []
        )],
        segments: [], transaction_sets: []
      )
      out = Generation::ElementGenerator.new(rel).generate
      expect(out).to include('E9999 ||= t::Nn.new(:E9999, "Synthetic Decimal", 1, 9, 3)')
    end

    it "emits the transaction set with nested loop and correct positions" do
      ts = release.transaction_sets.find { |t| t.code == "204" }
      out = Generation::DefinitionGenerator.new(ts).generate
      expect(out).to include('SM204 = b.build("SM", "204", "Motor Carrier Load Tender",')
      expect(out).to include('s::ST.use(100, r::Mandatory, d::RepeatCount.bounded(1))')
      expect(out).to include('d::LoopDef.build("N1", d::RepeatCount.unbounded,')
      expect(out).to include('s::REF.use(100, r::Optional, d::RepeatCount.bounded(1))')
    end

    it "emits two distinct LoopDefs for same-ID loops at different nesting positions" do
      ts = release.transaction_sets.find { |t| t.code == "123" }
      out = Generation::DefinitionGenerator.new(ts).generate
      expect(out).to include('d::LoopDef.build("REF", d::RepeatCount.bounded(200),')
      expect(out).to include('d::LoopDef.build("REF", d::RepeatCount.bounded(20),')
    end

    it "prefixes 'TS' for a transaction set with no functional group" do
      ts = release.transaction_sets.find { |t| t.code == "997" }
      gen = Generation::DefinitionGenerator.new(ts)
      expect(gen.constant_name).to eq("TS997")
      expect(gen.output_path).to eq("edi/fifty_ten/standards/TS997.rb")
      expect(gen.generate).to include('TS997 = b.build("", "997", "Functional Acknowledgment",')
    end

    it "honors a custom namespace" do
      out = Generation::ElementGenerator.new(release, namespace: "Acme").generate
      expect(out).to include("module Acme")
      expect(out).to include("t = Acme::FiftyTen::ElementTypes")
      expect(Generation::ElementGenerator.new(release, namespace: "Acme").output_path)
        .to eq("acme/fifty_ten/element_defs.rb")
    end

    it "rejects a nested namespace (would generate uncompilable `module A::B`)" do
      expect { Generation::ElementGenerator.new(release, namespace: "Acme::Grammars").generate }
        .to raise_error(ArgumentError, /single Ruby constant name/)
    end

    it "detects the repetition separator (I65 at ISA position 11)" do
      out = Generation::InterchangeGenerator.new(release).generate
      expect(out).to include("module FiveOhOne")
      expect(out).to include("Stupidedi::Reader::Separators.new(isa.element(16).to_s, isa.element(11).to_s, nil, nil)")
      expect(out).to include('end.new "00501",')
      # replace_separators re-stamps ISA11 with the repetition separator (and
      # ISA16 with the component separator) on a repetition-enabled release.
      expect(out).to include("isa.element(11).copy(:value => separators.repetition),")
      expect(out).to include("isa.element(16).copy(:value => separators.component)]")
    end

    it "leaves ISA11 untouched for a release with no repetition separator" do
      isa = Generation::Models::Segment.new(
        code: "ISA", name: "Interchange Control Header", purpose: nil, syntax_notes: [],
        element_uses: (1..16).map do |i|
          Generation::Models::ElementUse.new(
            position: i, requirement: "Mandatory", max_reps: 1,
            element: Generation::Models::Element.new(
              code: (i == 11 ? "I10" : "I#{i}"), name: "x", description: nil,
              x12_type: nil, is_composite: false, min_length: 1, max_length: 1,
              digits: nil, element_codes: [], component_uses: []
            )
          )
        end
      )
      rel = Generation::Models::Release.new(code: "005010", elements: [], segments: [isa], transaction_sets: [])
      out = Generation::InterchangeGenerator.new(rel).generate

      expect(out).to include("isa.element(11),")
      expect(out).not_to include("separators.repetition")
      expect(out).to include("isa.element(16).copy(:value => separators.component)]")
    end

    it "emits the functional group def with the full release code" do
      out = Generation::FunctionalGroupGenerator.new(release).generate
      expect(out).to include('end.new "005010",')
    end

    it "raises on an unsupported release" do
      bad = Generation::Models::Release.new(code: "999999", elements: [], segments: [], transaction_sets: [])
      expect { Generation::ElementGenerator.new(bad).generate }
        .to raise_error(ArgumentError, /Unsupported release/)
    end
  end

  describe "a full run" do
    around do |example|
      Dir.mktmpdir do |out|
        @out = out
        @results = Generation.run(table_data: fixture_dir, release: "005010", out: out, logger: ->(_) {})
        example.run
      end
    end

    it "writes the expected grammar tree" do
      relative = @results.map { |r| r.path.sub("#{@out}/", "") }.sort
      expect(relative).to eq(%w[
        edi/fifty_ten.rb
        edi/fifty_ten/element_defs.rb
        edi/fifty_ten/element_reqs.rb
        edi/fifty_ten/element_types.rb
        edi/fifty_ten/functional_group_def.rb
        edi/fifty_ten/segment_defs.rb
        edi/fifty_ten/segment_reqs.rb
        edi/fifty_ten/standards/SM204.rb
        edi/fifty_ten/standards/TS123.rb
        edi/fifty_ten/standards/TS997.rb
        edi/fifty_ten/syntax_notes.rb
        edi/interchanges/five_oh_one.rb
        edi/stupidedi_registration.rb
      ])
    end

    it "emits the registration with the expected version constants" do
      reg = File.read(File.join(@out, "edi/stupidedi_registration.rb"))
      expect(reg).to include('INTERCHANGE_VERSIONS = %w[00501].freeze')
      expect(reg).to include('FUNCTIONAL_GROUP_VERSIONS = %w[005010].freeze')
      expect(reg).to include('x.register("005010", "SM", "204") { Edi::FiftyTen::Standards::SM204 }')
    end

    it "generates the TS-prefixed standard but omits it from registration (no functional group)" do
      expect(File).to exist(File.join(@out, "edi/fifty_ten/standards/TS997.rb"))
      reg = File.read(File.join(@out, "edi/stupidedi_registration.rb"))
      expect(reg).not_to include("TS997")
      expect(reg).not_to include('"997"')
    end

    it "produces syntactically valid Ruby in every file", if: defined?(RubyVM::InstructionSequence) do
      @results.each do |result|
        expect { RubyVM::InstructionSequence.compile(result.content) }
          .not_to(raise_error, "syntax error in #{result.path}")
      end
    end

    it "loads into the engine and builds real schema definitions" do
      expect(integration_check(@out)).to include("INTEGRATION_OK")
    end

    it "omits the master loader by default" do
      expect(@results.map(&:path)).not_to include(File.join(@out, "edi.rb"))
    end
  end

  # The fixture's structure is release-agnostic, so pointing a second release
  # code at it exercises the per-release naming end to end: module, directory,
  # interchange version and registration keys.
  describe "a run against 003060" do
    it "generates a thirty_sixty tree under interchange 00306" do
      Dir.mktmpdir do |out|
        results = Generation.run(table_data: fixture_dir, release: "003060", out: out,
                                 write: false, logger: ->(_) {})

        expect(results.map(&:relative_path)).to include(
          "edi/thirty_sixty.rb",
          "edi/thirty_sixty/element_defs.rb",
          "edi/thirty_sixty/standards/SM204.rb",
          "edi/interchanges/three_oh_six.rb"
        )

        reg = results.find { |r| r.relative_path == "edi/stupidedi_registration.rb" }
        expect(reg.content).to include('INTERCHANGE_VERSIONS = %w[00306].freeze')
        expect(reg.content).to include('FUNCTIONAL_GROUP_VERSIONS = %w[003060].freeze')
        expect(reg.content).to include('x.register("003060", "SM", "204") { Edi::ThirtySixty::Standards::SM204 }')
      end
    end
  end

  describe "with a master loader" do
    around do |example|
      Dir.mktmpdir do |out|
        @out = out
        @results = Generation.run(table_data: fixture_dir, release: "005010", out: out,
                                  master_loader: true, logger: ->(_) {})
        example.run
      end
    end

    it "emits a single-require entry file" do
      expect(@results.map { |r| r.path.sub("#{@out}/", "") }).to include("edi.rb")
      loader = File.read(File.join(@out, "edi.rb"))
      expect(loader).to include('require "edi/fifty_ten"')
      expect(loader).to include('require "edi/interchanges/five_oh_one"')
      expect(loader).to include('require "edi/fifty_ten/standards/SM204"')
      expect(loader).to include('require "edi/stupidedi_registration"')
    end

    it "loads the whole grammar from a single require" do
      gem_lib = File.expand_path("../../../../lib", __dir__)
      driver = <<~RUBY
        $LOAD_PATH.unshift(#{@out.inspect})
        require "edi"
        config = Stupidedi::Config.new
        Edi::StupidediRegistration.register(config)
        ok = Edi::FiftyTen::Standards::SM204.is_a?(Stupidedi::Schema::TransactionSetDef) &&
             Edi::Interchanges::FiveOhOne::InterchangeDef.is_a?(Stupidedi::Schema::InterchangeDef)
        puts(ok ? "INTEGRATION_OK" : "INTEGRATION_FAIL")
      RUBY
      out = `#{Shellwords.escape(RbConfig.ruby)} -I#{Shellwords.escape(gem_lib)} -r tediparse -e #{Shellwords.escape(driver)} 2>&1`
      expect(out).to include("INTEGRATION_OK")
    end
  end

  describe "validation and dry-run" do
    it "fails fast when the table-data directory yields no data" do
      Dir.mktmpdir do |empty_in|
        Dir.mktmpdir do |out|
          expect { Generation.run(table_data: empty_in, release: "005010", out: out, logger: ->(_) {}) }
            .to raise_error(ArgumentError, /No X12 table data found/)
          expect(Dir.children(out)).to be_empty # nothing written
        end
      end
    end

    it "rejects a nested namespace before reading anything" do
      Dir.mktmpdir do |out|
        expect do
          Generation.run(table_data: fixture_dir, release: "005010", out: out,
                         namespace: "Acme::Grammars", logger: ->(_) {})
        end.to raise_error(ArgumentError, /single Ruby constant name/)
      end
    end

    it "previews an accurate registration in --dry-run (write: false) without writing" do
      Dir.mktmpdir do |out|
        results = Generation.run(table_data: fixture_dir, release: "005010", out: out,
                                 write: false, master_loader: true, logger: ->(_) {})
        reg = results.find { |r| r.relative_path == "edi/stupidedi_registration.rb" }
        loader = results.find { |r| r.relative_path == "edi.rb" }

        # The disk-scanning generators see the staged tree, so the preview is real.
        expect(reg.content).to include('INTERCHANGE_VERSIONS = %w[00501].freeze')
        expect(reg.content).to include('x.register("005010", "SM", "204")')
        expect(loader.content).to include('require "edi/fifty_ten/standards/SM204"')

        # ...but nothing is actually written.
        expect(Dir.children(out)).to be_empty
        expect(results.map(&:written)).to all(be(false))
      end
    end
  end

  describe "multi-release aggregation" do
    # The registration/master loader are whole-tree artifacts: generating one
    # release must not drop the others already present under out.
    it "unions the generated release with releases already present under out" do
      Dir.mktmpdir do |out|
        seed_release(out, "forty_ten", "AA999", "four_oh_one")

        Generation.run(table_data: fixture_dir, release: "005010", out: out, master_loader: true, logger: ->(_) {})

        reg = File.read(File.join(out, "edi/stupidedi_registration.rb"))
        expect(reg).to include('INTERCHANGE_VERSIONS = %w[00401 00501].freeze')
        expect(reg).to include('FUNCTIONAL_GROUP_VERSIONS = %w[004010 005010].freeze')
        expect(reg).to include('x.register("004010", "AA", "999") { Edi::FortyTen::Standards::AA999 }')
        expect(reg).to include('x.register("005010", "SM", "204") { Edi::FiftyTen::Standards::SM204 }')

        loader = File.read(File.join(out, "edi.rb"))
        expect(loader).to include('require "edi/forty_ten"')
        expect(loader).to include('require "edi/fifty_ten"')

        # The pre-existing release's files are left untouched.
        expect(File).to exist(File.join(out, "edi/forty_ten/standards/AA999.rb"))
      end
    end

    it "reflects the union in a dry-run preview without writing the new release" do
      Dir.mktmpdir do |out|
        seed_release(out, "forty_ten", "AA999", "four_oh_one")

        results = Generation.run(table_data: fixture_dir, release: "005010", out: out, write: false, logger: ->(_) {})
        reg = results.find { |r| r.relative_path == "edi/stupidedi_registration.rb" }

        expect(reg.content).to include('FUNCTIONAL_GROUP_VERSIONS = %w[004010 005010].freeze')
        expect(reg.content).to include('x.register("004010", "AA", "999") { Edi::FortyTen::Standards::AA999 }')
        expect(reg.content).to include('x.register("005010", "SM", "204") { Edi::FiftyTen::Standards::SM204 }')

        # Nothing for the previewed release was written.
        expect(File).not_to exist(File.join(out, "edi/fifty_ten"))
      end
    end

    it "shadows an on-disk release with the freshly generated one (regeneration)" do
      Dir.mktmpdir do |out|
        # A stale fifty_ten already on disk, carrying a transaction set the
        # current table data no longer produces.
        seed_release(out, "fifty_ten", "ZZ888", "five_oh_one")

        Generation.run(table_data: fixture_dir, release: "005010", out: out, logger: ->(_) {})

        reg = File.read(File.join(out, "edi/stupidedi_registration.rb"))
        # The freshly generated set wins...
        expect(reg).to include('x.register("005010", "SM", "204")')
        # ...the stale entry is shadowed out of the registration...
        expect(reg).not_to include("ZZ888")
        # ...and the orphaned file is removed from the tree (replace, not merge).
        expect(File).not_to exist(File.join(out, "edi/fifty_ten/standards/ZZ888.rb"))
        # fifty_ten registered exactly once (no duplicate from the two roots).
        expect(reg.scan('x.register("005010") {').size).to eq(1)
      end
    end

    it "Generation.register rebuilds the registration from the whole live tree" do
      Dir.mktmpdir do |out|
        seed_release(out, "forty_ten", "AA999", "four_oh_one")
        seed_release(out, "fifty_ten", "SM204", "five_oh_one")

        Generation.register(out: out, logger: ->(_) {})

        reg = File.read(File.join(out, "edi/stupidedi_registration.rb"))
        expect(reg).to include('FUNCTIONAL_GROUP_VERSIONS = %w[004010 005010].freeze')
        expect(reg).to include('x.register("004010", "AA", "999") { Edi::FortyTen::Standards::AA999 }')
        expect(reg).to include('x.register("005010", "SM", "204") { Edi::FiftyTen::Standards::SM204 }')

        # No master loader present -> none is created.
        expect(File).not_to exist(File.join(out, "edi.rb"))
      end
    end

    it "Generation.register keeps the master loader in sync when one is present" do
      Dir.mktmpdir do |out|
        seed_release(out, "forty_ten", "AA999", "four_oh_one")
        seed_release(out, "fifty_ten", "SM204", "five_oh_one")
        # A stale master loader that only knows about forty_ten.
        File.write(File.join(out, "edi.rb"), %(require "tediparse"\nrequire "edi/forty_ten"\n))

        Generation.register(out: out, logger: ->(_) {})

        loader = File.read(File.join(out, "edi.rb"))
        expect(loader).to include('require "edi/forty_ten"')
        expect(loader).to include('require "edi/fifty_ten"') # picked up the release the stale loader missed
        expect(loader).to include('require "edi/stupidedi_registration"')
      end
    end
  end

  # Writes a minimal placeholder grammar tree for one release under out/edi so the
  # whole-tree scanners (registration/master loader) see it. Only the file/dir
  # names matter to those scanners, not the contents.
  def seed_release(out, version_dir, standard, interchange_file)
    base = File.join(out, "edi")
    FileUtils.mkdir_p(File.join(base, version_dir, "standards"))
    FileUtils.mkdir_p(File.join(base, "interchanges"))
    File.write(File.join(base, version_dir, "functional_group_def.rb"), "# placeholder\n")
    File.write(File.join(base, version_dir, "standards", "#{standard}.rb"), "# placeholder\n")
    File.write(File.join(base, "interchanges", "#{interchange_file}.rb"), "# placeholder\n")
  end

  # Loads the freshly generated grammar in a clean child process (so the Edi::*
  # constants never leak into the test process), wires up a Config, and confirms
  # the generated code constructs real engine objects.
  def integration_check(out)
    gem_lib = File.expand_path("../../../../lib", __dir__)
    driver = <<~RUBY
      $LOAD_PATH.unshift(#{out.inspect})
      require "edi/fifty_ten"
      Dir[File.join(#{out.inspect}, "edi/interchanges/*.rb")].sort.each { |f| require f }
      Dir[File.join(#{out.inspect}, "edi/fifty_ten/standards/*.rb")].sort.each { |f| require f }
      require "edi/stupidedi_registration"

      config = Stupidedi::Config.new
      Edi::StupidediRegistration.register(config)

      ok = Edi::FiftyTen::Standards::SM204.is_a?(Stupidedi::Schema::TransactionSetDef) &&
           Edi::Interchanges::FiveOhOne::InterchangeDef.is_a?(Stupidedi::Schema::InterchangeDef) &&
           Edi::FiftyTen::FunctionalGroupDef.is_a?(Stupidedi::Schema::FunctionalGroupDef)
      puts(ok ? "INTEGRATION_OK" : "INTEGRATION_FAIL")
    RUBY

    `#{Shellwords.escape(RbConfig.ruby)} -I#{Shellwords.escape(gem_lib)} -r tediparse -e #{Shellwords.escape(driver)} 2>&1`
  end
end
