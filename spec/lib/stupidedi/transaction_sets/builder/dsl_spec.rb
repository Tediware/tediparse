describe Stupidedi::TransactionSets::Builder::Dsl do

  context 'with the most basic build' do
    SegmentReqs = Stupidedi::TransactionSets::Common::Implementations::SegmentReqs

    # Inline 3-element synthetic ST (id + control + version) so the DSL's
    # `element(..., values("..."))` path is exercised on the third element.
    # We don't lean on Synthetic::SegmentDefs::ST here because that one
    # mirrors the basic 2-element X12 wire shape; this spec is unit-testing
    # the DSL, so the input grammar shape can be whatever stresses the DSL.
    let(:st_3el) do
      de = Stupidedi::Versions::Common::ElementReqs
      rc = Stupidedi::Schema::RepeatCount
      an = Stupidedi::Versions::Common::ElementTypes::AN
      Stupidedi::Schema::SegmentDef.build(:ST, "Transaction Set Header", "",
        an.new(:SY_ST_ID,      "Transaction Set Identifier Code",   3, 3).simple_use(de::Mandatory, rc.bounded(1)),
        an.new(:SY_ST_CTRL,    "Transaction Set Control Number",    4, 9).simple_use(de::Mandatory, rc.bounded(1)),
        an.new(:SY_ST_VERSION, "Implementation Convention Reference", 1, 35).simple_use(de::Optional,  rc.bounded(1)))
    end

    let(:definition) do
      e   = Stupidedi::TransactionSets::Common::Implementations::ElementReqs
      st  = st_3el
      rep = Stupidedi::Schema::RepeatCount
      described_class.build("HH", "100", "Test Fake Document") do
        table_header("1 - Header") do
          segment(100, st, "Transaction Set Header", SegmentReqs::Required, rep.bounded(1)) do
            element(e::Required, "Transaction Set Identifier Code", values("100"))
            element(e::Required, "Transaction Set Control Number")
            element(e::Required, "Version, Release, or Industry Number", values("1000"))
          end
        end
      end
    end

    describe 'the definition as a whole' do

      subject { definition }

      it 'raises no error on initialization' do
        expect { subject }.to_not raise_error
      end

      it { is_expected.to be_definition }
    end

    describe 'the first table' do
      subject { definition.children.first }
      it { is_expected.to be_table }
      it { is_expected.to be_definition }

      describe 'the first segment in the first table' do
        subject { definition.children.first.children.first }
        it { is_expected.to_not be_repeatable }
        it { is_expected.to be_definition }
        it { is_expected.to be_segment }
        it do
          is_expected.to(
            have_attributes(
              repeat_count: 1,
              requirement: SegmentReqs::Required,
              position: 100,
              name: "Transaction Set Header",
              descriptor: "segment ST Transaction Set Header",
              id: :ST
            )
          )
        end
      end
    end
  end
end
