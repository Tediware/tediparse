# frozen_string_literal: true

describe Stupidedi::Schema::LoopDef do
  using Stupidedi::Refinements

  let(:d) { Stupidedi::Schema }
  let(:r) { Stupidedi::Versions::Common::SegmentReqs }

  # Inline synthetic SegmentDefs — these tests exercise LoopDef's structural
  # validation only, so the segments need not match any X12 grammar. Two-letter
  # synthetic IDs (AA, BB, CC, DD, EE, FF, GG) keep them visually distinct from
  # real X12 designators.
  let(:s) do
    t  = Stupidedi::Versions::Common::ElementTypes
    de = Stupidedi::Versions::Common::ElementReqs
    text = t::AN.new(:DE_TEXT, "Synthetic Text", 1, 30)
    Module.new do
      const_set(:AA, Stupidedi::Schema::SegmentDef.build(:AA, "Synthetic AA", "",
                       text.simple_use(de::Optional, Stupidedi::Schema::RepeatCount.bounded(1))))
      const_set(:BB, Stupidedi::Schema::SegmentDef.build(:BB, "Synthetic BB", "",
                       text.simple_use(de::Optional, Stupidedi::Schema::RepeatCount.bounded(1))))
      const_set(:CC, Stupidedi::Schema::SegmentDef.build(:CC, "Synthetic CC", "",
                       text.simple_use(de::Optional, Stupidedi::Schema::RepeatCount.bounded(1))))
      const_set(:DD, Stupidedi::Schema::SegmentDef.build(:DD, "Synthetic DD", "",
                       text.simple_use(de::Optional, Stupidedi::Schema::RepeatCount.bounded(1))))
      const_set(:EE, Stupidedi::Schema::SegmentDef.build(:EE, "Synthetic EE", "",
                       text.simple_use(de::Optional, Stupidedi::Schema::RepeatCount.bounded(1))))
      const_set(:FF, Stupidedi::Schema::SegmentDef.build(:FF, "Synthetic FF", "",
                       text.simple_use(de::Optional, Stupidedi::Schema::RepeatCount.bounded(1))))
      const_set(:GG, Stupidedi::Schema::SegmentDef.build(:GG, "Synthetic GG", "",
                       text.simple_use(de::Optional, Stupidedi::Schema::RepeatCount.bounded(1))))
    end
  end

  describe ".build" do
    context "with segments only before child loops" do
      it "succeeds" do
        expect {
          d::LoopDef.build("0100", d::RepeatCount.bounded(1),
            s::AA.use(100, r::Mandatory, d::RepeatCount.bounded(1)),
            s::BB.use(200, r::Optional,  d::RepeatCount.bounded(1)),
            s::CC.use(300, r::Optional,  d::RepeatCount.bounded(1)),
            d::LoopDef.build("0110", d::RepeatCount.bounded(5),
              s::DD.use(400, r::Optional, d::RepeatCount.bounded(1))))
        }.not_to raise_error
      end
    end

    context "with trailer segments after all child loops" do
      it "succeeds" do
        expect {
          d::LoopDef.build("0100", d::RepeatCount.bounded(1),
            s::AA.use(100, r::Mandatory, d::RepeatCount.bounded(1)),
            d::LoopDef.build("0110", d::RepeatCount.bounded(5),
              s::DD.use(200, r::Optional, d::RepeatCount.bounded(1))),
            s::EE.use(300, r::Optional, d::RepeatCount.bounded(1)))
        }.not_to raise_error
      end
    end

    context "with interleaved segments and loops" do
      it "succeeds when a segment appears between two child loops" do
        # This is valid per X12 standard but previously raised InvalidSchemaError.
        # Fix tracked in commit df0c4da4 (SO317 5010 standard).
        expect {
          d::LoopDef.build("0100", d::RepeatCount.bounded(1),
            s::AA.use(100, r::Mandatory, d::RepeatCount.bounded(1)),
            d::LoopDef.build("0110", d::RepeatCount.bounded(5),
              s::BB.use(200, r::Optional, d::RepeatCount.bounded(1))),
            s::EE.use(300, r::Optional, d::RepeatCount.bounded(1)),
            d::LoopDef.build("0120", d::RepeatCount.bounded(5),
              s::DD.use(400, r::Optional, d::RepeatCount.bounded(1))))
        }.not_to raise_error
      end

      it "succeeds with multiple interleaved segments and loops" do
        # Pattern: segment -> loop -> segment -> loop -> segment -> loop
        expect {
          d::LoopDef.build("0300", d::RepeatCount.bounded(1),
            s::AA.use(100, r::Mandatory, d::RepeatCount.bounded(1)),
            s::BB.use(200, r::Optional,  d::RepeatCount.bounded(1)),
            d::LoopDef.build("0305", d::RepeatCount.bounded(5),
              s::EE.use(300, r::Optional, d::RepeatCount.bounded(1))),
            s::CC.use(400, r::Optional, d::RepeatCount.bounded(1)),
            d::LoopDef.build("0310", d::RepeatCount.bounded(5),
              s::DD.use(500, r::Optional, d::RepeatCount.bounded(1))),
            s::FF.use(600, r::Optional, d::RepeatCount.bounded(1)),
            d::LoopDef.build("0320", d::RepeatCount.bounded(5),
              s::GG.use(700, r::Optional, d::RepeatCount.bounded(1))))
        }.not_to raise_error
      end
    end

    context "validation" do
      it "requires the first child to be a SegmentUse" do
        expect {
          d::LoopDef.build("0100", d::RepeatCount.bounded(1),
            d::LoopDef.build("0110", d::RepeatCount.bounded(5),
              s::AA.use(100, r::Mandatory, d::RepeatCount.bounded(1))))
        }.to raise_error(Stupidedi::Exceptions::InvalidSchemaError, /first child must be a SegmentUse/)
      end

      it "requires the first segment to have RepeatCount.bounded(1)" do
        expect {
          d::LoopDef.build("0100", d::RepeatCount.bounded(1),
            s::AA.use(100, r::Mandatory, d::RepeatCount.bounded(5)))
        }.to raise_error(Stupidedi::Exceptions::InvalidSchemaError, /RepeatCount\.bounded\(1\)/)
      end
    end
  end
end
