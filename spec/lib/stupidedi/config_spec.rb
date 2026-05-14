describe "Stupidedi::Config registries" do
  let(:config) { Stupidedi::Config.new }

  describe "InterchangeConfig#register" do
    it "raises ArgumentError when neither a definition nor a block is given" do
      expect {
        config.interchange.register("DEMO01")
      }.to raise_error(ArgumentError, /InterchangeConfig#register\("DEMO01"\)/)
    end

    it "stores the definition when given positionally" do
      definition = Object.new
      config.interchange.register("DEMO01", definition)
      expect(config.interchange.at("DEMO01")).to equal(definition)
    end

    it "stores the constructor when given as a block" do
      definition = Object.new
      config.interchange.register("DEMO01") { definition }
      expect(config.interchange.at("DEMO01")).to equal(definition)
    end
  end

  describe "FunctionalGroupConfig#register" do
    it "raises ArgumentError when neither a definition nor a block is given" do
      expect {
        config.functional_group.register("005010")
      }.to raise_error(ArgumentError, /FunctionalGroupConfig#register\("005010"\)/)
    end

    it "stores the definition when given positionally" do
      definition = Object.new
      config.functional_group.register("005010", definition)
      expect(config.functional_group.at("005010")).to equal(definition)
    end

    it "stores the constructor when given as a block" do
      definition = Object.new
      config.functional_group.register("005010") { definition }
      expect(config.functional_group.at("005010")).to equal(definition)
    end
  end

  describe "TransactionSetConfig#register" do
    it "raises ArgumentError when neither a definition nor a block is given" do
      expect {
        config.transaction_set.register("005010", "LO", "100")
      }.to raise_error(
        ArgumentError,
        /TransactionSetConfig#register\("005010", "LO", "100"\)/
      )
    end

    it "stores the definition when given positionally" do
      definition = Object.new
      config.transaction_set.register("005010", "LO", "100", definition)
      expect(config.transaction_set.at("005010", "LO", "100")).to equal(definition)
    end

    it "stores the constructor when given as a block" do
      definition = Object.new
      config.transaction_set.register("005010", "LO", "100") { definition }
      expect(config.transaction_set.at("005010", "LO", "100")).to equal(definition)
    end
  end
end
