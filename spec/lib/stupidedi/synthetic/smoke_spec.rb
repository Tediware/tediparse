describe "Synthetic Demo grammar smoke tests" do
  using Stupidedi::Refinements

  let(:fixtures_dir) { File.expand_path("../../../../fixtures/demo", __FILE__) }
  let(:config)       { Synthetic.config }

  def parse(path)
    input = File.read(path)
    Stupidedi::Parser.build(config).read(Stupidedi::Reader.build(input))
  end

  def collect_failures(machine)
    failures = []
    walk = lambda do |z|
      node = z.node
      failures << node if node.is_a?(Stupidedi::Values::InvalidSegmentVal) ||
                          node.is_a?(Stupidedi::Values::InvalidEnvelopeVal)
      if z.respond_to?(:children) && !z.leaf?
        z.children.each{|c| walk.call(c) }
      end
    end
    walk.call(machine.zipper.fetch.root)
    failures
  end

  def assert_no_failures(machine)
    failures = collect_failures(machine)
    expect(failures).to be_empty, "expected no failures, found #{failures.size}: #{failures.map(&:class)}"
  end

  context "minimal.edi (just envelope + empty transaction set)" do
    it "parses without errors" do
      machine, result = parse(File.join(fixtures_dir, "minimal.edi"))
      expect(result.fatal?).to be false
      assert_no_failures(machine)
    end
  end

  def locate(machine, *path)
    machine.first.flatmap{|m| m.sequence(*path) }.fetch
  end

  context "primary_loop.edi (single qualifier-discriminated loop)" do
    it "binds LO to the primary slot at position 300" do
      machine, result = parse(File.join(fixtures_dir, "primary_loop.edi"))
      expect(result.fatal?).to be false
      assert_no_failures(machine)

      lo = locate(machine, :GS, :ST, :HH, :LO)
      expect(lo.zipper.fetch.node.usage.position).to eq(300)
    end
  end

  context "override_only.edi (override loop only)" do
    it "binds LO to the override slot at position 600" do
      machine, result = parse(File.join(fixtures_dir, "override_only.edi"))
      expect(result.fatal?).to be false
      assert_no_failures(machine)

      lo = locate(machine, :GS, :ST, :LO)
      expect(lo.zipper.fetch.node.usage.position).to eq(600)
    end
  end

  context "both_loops_interleaved.edi (primary + FT + override)" do
    it "parses with FT segment between the two loops" do
      machine, result = parse(File.join(fixtures_dir, "both_loops_interleaved.edi"))
      expect(result.fatal?).to be false
      assert_no_failures(machine)

      ft = locate(machine, :GS, :ST, :HH, :LO, :IT, :FT)
      expect(ft.zipper.fetch.node.usage.position).to eq(500)
    end
  end

  context "duplicate_slot_earlier.edi (only the earlier NX slot is filled)" do
    it "binds the single NX to the earlier slot (position 900) — the tediparse-04 fix" do
      machine, result = parse(File.join(fixtures_dir, "duplicate_slot_earlier.edi"))
      expect(result.fatal?).to be false
      assert_no_failures(machine)

      nx = locate(machine, :GS, :ST, :LO, :NX)
      expect(nx.zipper.fetch.node.usage.position).to eq(900)
    end
  end

  context "duplicate_slot_both.edi (both NX slots filled)" do
    it "binds the two NX segments to positions 900 and 1000 in order" do
      machine, result = parse(File.join(fixtures_dir, "duplicate_slot_both.edi"))
      expect(result.fatal?).to be false
      assert_no_failures(machine)

      first  = locate(machine, :GS, :ST, :LO, :NX)
      second = first.find(:NX).fetch
      expect([first.zipper.fetch.node.usage.position,
              second.zipper.fetch.node.usage.position]).to eq([900, 1000])
    end
  end

  context "unknown_st01.edi (transaction set 999 not in config)" do
    it "produces a parse tree containing an InvalidSegmentVal for ST" do
      machine, result = parse(File.join(fixtures_dir, "unknown_st01.edi"))
      expect(result.fatal?).to be false
      failures = collect_failures(machine)
      expect(failures.any?{|f| f.is_a?(Stupidedi::Values::InvalidSegmentVal) }).to be true
    end
  end

  describe "round-trip" do
    %w[
      minimal.edi
      primary_loop.edi
      override_only.edi
      both_loops_interleaved.edi
      duplicate_slot_earlier.edi
      duplicate_slot_both.edi
    ].each do |name|
      it "round-trips #{name} byte-for-byte" do
        path     = File.join(fixtures_dir, name)
        original = File.read(path)
        machine, result = parse(path)
        expect(result.fatal?).to be false

        separators = Stupidedi::Reader::Separators.new(":", "^", "*", "~")
        root       = machine.zipper.fetch.root
        rewritten  = Stupidedi::Writer::Default.new(root, separators).write

        # Tolerate a trailing newline on the fixture file
        expect(rewritten.strip).to eq(original.strip)
      end
    end
  end
end
