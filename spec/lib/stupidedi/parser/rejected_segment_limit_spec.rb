# frozen_string_literal: true
require "spec_helper"

describe "Parser read with max_rejected_segments" do
  using Stupidedi::Refinements

  let(:fixtures_dir) { File.expand_path("../../../../fixtures/demo", __FILE__) }
  let(:config)       { Synthetic.config }

  # ST*999 is not registered, so the ST and everything up to GE is rejected:
  # the ST, each body segment, and the SE.
  def unknown_set(body_count)
    "ISA*00*          *00*          *ZZ*SENDER         *ZZ*RECEIVER       " \
    "*250101*0830*^*DEMO01*000000007*0*T*:~" \
    "GS*ZZ*SENDER*RECEIVER*20250101*0830*7*X*DEMO01~" \
    "ST*999*0001~" +
    Array.new(body_count) { |i| "IT*P:item-#{i}*1*10~" }.join +
    "SE*#{body_count + 2}*0001~GE*1*7~IEA*1*000000007~"
  end

  def read(input, options = {})
    Stupidedi::Parser.build(config).read(Stupidedi::Reader.build(input), options)
  end

  def invalid_segment_count(machine)
    count = 0
    walk  = lambda do |z|
      count += 1 if z.node.is_a?(Stupidedi::Values::InvalidSegmentVal)
      z.children.each { |c| walk.call(c) } unless z.leaf?
    end
    walk.call(machine.zipper.fetch.root)
    count
  end

  it "raises once more than the limit of segments is rejected" do
    expect { read(unknown_set(50), max_rejected_segments: 10) }.to raise_error(
      Stupidedi::Exceptions::RejectedSegmentLimitError,
      /\Astopped parsing after 11 rejected segments; the first was ST at line \d+.*\(unknown transaction set .*"999"\)\z/
    ) { |e| expect([e.count, e.first.id]).to eq([11, :ST]) }
  end

  it "is a ParseError" do
    expect { read(unknown_set(50), max_rejected_segments: 10) }
      .to raise_error(Stupidedi::Exceptions::ParseError)
  end

  it "parses as before when the rejected segments are within the limit" do
    limited,   = read(unknown_set(8), max_rejected_segments: 10)
    unlimited, = read(unknown_set(8))

    expect(invalid_segment_count(limited)).to eq(10)
    expect(invalid_segment_count(limited)).to eq(invalid_segment_count(unlimited))
  end

  it "does not limit anything when the option is absent" do
    machine, result = read(unknown_set(500))

    expect(result.fatal?).to be false
    expect(invalid_segment_count(machine)).to eq(502)
  end

  it "counts only the rejected segment when its accepted siblings follow it" do
    stray = File.read(File.join(fixtures_dir, "primary_loop.edi"))
      .sub("LO*P*Primary block~", "LO*P*Primary block~ZZ*1~")
    machine, = read(stray)
    expect(invalid_segment_count(machine)).to eq(1)

    expect { read(stray, max_rejected_segments: 1) }.not_to raise_error
    expect { read(stray, max_rejected_segments: 0) }.to raise_error(
      Stupidedi::Exceptions::RejectedSegmentLimitError
    ) { |e| expect([e.count, e.first.id]).to eq([1, :ZZ]) }
  end

  it "does not count segments that parse" do
    machine, result = read(File.read(File.join(fixtures_dir, "primary_loop.edi")),
                           max_rejected_segments: 0)

    expect(result.fatal?).to be false
    expect(invalid_segment_count(machine)).to eq(0)
  end
end
