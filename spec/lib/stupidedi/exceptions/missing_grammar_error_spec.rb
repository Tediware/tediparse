describe Stupidedi::Exceptions::MissingGrammarError do
  describe "DEFAULT_MESSAGE" do
    subject { described_class::DEFAULT_MESSAGE }

    it { is_expected.to be_a(String).and(satisfy { |s| s.include?("tediparse") }) }
    it { is_expected.to satisfy { |s| s.include?("Stupidedi::Config") } }
    it { is_expected.to satisfy { |s| s.include?("README") } }
  end

  describe "constructors" do
    it "uses DEFAULT_MESSAGE when no context is given" do
      expect(described_class.new.message).to eq(described_class::DEFAULT_MESSAGE)
    end

    it "appends the resolution context when one is given" do
      err = described_class.new("Stupidedi::Versions::FiftyTen")
      expect(err.message).to include(described_class::DEFAULT_MESSAGE)
      expect(err.message).to include("(while resolving Stupidedi::Versions::FiftyTen)")
    end

    it "is a StupidediError so existing rescue StupidediError clauses catch it" do
      expect(described_class.new).to be_a(Stupidedi::Exceptions::StupidediError)
    end
  end

  describe "const_missing hooks" do
    {
      Stupidedi                  => %i[Editor Contrib Guides],
      Stupidedi::Interchanges    => %i[TwoHundred ThreeHundred FourHundred FourOhOne FiveOhOne],
      Stupidedi::Versions        => %i[TwoThousandOne ThirtyTen ThirtyForty ThirtyFifty FortyTen FiftyTen FunctionalGroups Interchanges],
      Stupidedi::TransactionSets => %i[TwoThousandOne ThirtyTen ThirtyForty ThirtyFifty FortyTen FiftyTen],
    }.each do |namespace, removed|
      context "on #{namespace}" do
        removed.each do |name|
          it "raises MissingGrammarError naming #{name} when referenced" do
            expect { namespace.const_get(name) }
              .to raise_error(described_class, /#{namespace}::#{name}/)
          end
        end

        it "falls back to NameError for a genuinely undefined constant" do
          # NotARealRemovedEra is not in REMOVED_ERAS so Ruby's normal NameError
          # behavior should surface — important so that legitimate typos in user
          # code still produce the standard error.
          expect { namespace.const_get(:NotARealRemovedEra) }.to raise_error(NameError)
        end
      end
    end
  end

  describe "Config factories return empty configs" do
    # Config.default / hipaa / contrib are preserved for source compatibility
    # with upstream stupidedi, but they no longer register any grammars — see
    # lib/stupidedi/config.rb. Parser-driven lookups against the returned
    # config must hit the empty-registry branch and surface DEFAULT_MESSAGE.
    %i[default hipaa contrib].each do |factory|
      it "Config.#{factory} returns an empty Config" do
        cfg = Stupidedi::Config.send(factory)
        expect(cfg.interchange).to be_empty
        expect(cfg.functional_group).to be_empty
        expect(cfg.transaction_set).to be_empty
      end
    end
  end

  describe "parser surface against an empty Config" do
    def parse(config, edi)
      Stupidedi::Parser.build(config).read(Stupidedi::Reader.build(edi))
    end

    def collect_reasons(machine)
      reasons = []
      walk = lambda do |z|
        node = z.node
        reasons << node.reason if node.is_a?(Stupidedi::Values::InvalidSegmentVal)
        if z.respond_to?(:children) && !z.leaf?
          z.children.each { |c| walk.call(c) }
        end
      end
      walk.call(machine.zipper.fetch.root)
      reasons
    end

    let(:helpful_message) { Stupidedi::Exceptions::MissingGrammarError::DEFAULT_MESSAGE }

    let(:isa) do
      "ISA*00*          *00*          *ZZ*SENDER         *ZZ*RECEIVER       " \
      "*250101*0830*^*DEMO01*000000001*0*T*:~"
    end

    let(:gs) { "GS*ZZ*SENDER*RECEIVER*20250101*0830*1*X*DEMO01~" }
    let(:st) { "ST*100*0001~" }

    it "surfaces the helpful message when InterchangeConfig is empty" do
      machine, _result = parse(Stupidedi::Config.new, isa)
      expect(collect_reasons(machine)).to include(helpful_message)
    end

    it "surfaces the helpful message when FunctionalGroupConfig is empty" do
      config = Stupidedi::Config.new.customize do |c|
        c.interchange.register("DEMO01") { Synthetic::InterchangeDef }
      end

      machine, _result = parse(config, isa + gs)
      expect(collect_reasons(machine)).to include(helpful_message)
    end

    it "surfaces the helpful message when TransactionSetConfig is empty" do
      config = Stupidedi::Config.new.customize do |c|
        c.interchange.register("DEMO01")     { Synthetic::InterchangeDef }
        c.functional_group.register("DEMO01") { Synthetic::FunctionalGroupDef }
      end

      machine, _result = parse(config, isa + gs + st)
      expect(collect_reasons(machine)).to include(helpful_message)
    end
  end
end
