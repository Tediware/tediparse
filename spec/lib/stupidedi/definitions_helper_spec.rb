describe Definitions, "helper module" do
  using Stupidedi::Refinements
  include Definitions

  describe ".Element with a Symbol" do
    # Defends a previously-latent bug where the Symbol branch referenced an
    # undefined local `id` (it should have been `element`). The branch had
    # no caller in the spec suite when the bug was introduced.
    it "resolves the symbol against the local ElementDefs module" do
      use = self.Element(:DE_AN, Definitions::ElementReqs::Optional,
                         Stupidedi::Schema::RepeatCount.bounded(1))
      expect(use).to be_a(Stupidedi::Schema::SimpleElementUse)
      expect(use.definition).to be(Definitions::ElementDefs::DE_AN)
    end
  end

  describe ".Segment with a Symbol" do
    it "resolves :ST against the local SegmentDefs module (no FiftyTen dependency)" do
      use = Segment(10, :ST, Definitions::SegmentReqs::Mandatory,
                    Stupidedi::Schema::RepeatCount.bounded(1))
      expect(use).to be_a(Stupidedi::Schema::SegmentUse)
      expect(use.definition.id).to eq(:ST)
    end
  end
end
