# frozen_string_literal: true

describe Stupidedi::Schema::RepeatCount do
  let(:d) { Stupidedi::Schema }

  describe ".bounded" do
    it "returns Once for a single occurrence" do
      expect(d::RepeatCount.bounded(1)).to be(d::RepeatCount::Once)
    end

    it "returns a Bounded count above one" do
      count = d::RepeatCount.bounded(5)
      expect(count).to be_a(d::RepeatCount::Bounded)
      expect(count.max).to eq(5)
    end

    # A grammar that says "may occur zero times" is a grammar with an
    # unreachable element in it, so this is rejected at build time. The raise
    # named `Exception::InvalidSchemaError` until it was corrected: constant
    # lookup found ::Exception and every zero count surfaced as an opaque
    # NameError instead.
    it "rejects a zero count as an invalid schema" do
      expect { d::RepeatCount.bounded(0) }
        .to raise_error(Stupidedi::Exceptions::InvalidSchemaError, /must be positive/)
    end

    it "rejects a negative count as an invalid schema" do
      expect { d::RepeatCount.bounded(-1) }
        .to raise_error(Stupidedi::Exceptions::InvalidSchemaError, /must be positive/)
    end
  end

  describe ".unbounded" do
    it "includes any number of occurrences" do
      expect(d::RepeatCount.unbounded.include?(1_000)).to be(true)
    end
  end
end
