describe Stupidedi::TransactionSets::Validation::Ambiguity, "against the synthetic grammar" do
  it "flags AmbiguousDemo as a schema error and accepts a non-default interchange_def" do
    # Two LO openers at the same position both accept SD_KIND="P" — the
    # ValueBased ConstraintTable cannot pick between them. Passing
    # Synthetic::InterchangeDef as the third argument also exercises the
    # `interchange_def` parameter on Ambiguity.build / Ambiguity.mkconfig
    # (which otherwise defaults to the bundled 00501 envelope).
    expect do
      described_class.build(
        Synthetic::AmbiguousDemo,
        Synthetic::FunctionalGroupDef,
        Synthetic::InterchangeDef
      ).audit
    end.to raise_error(Stupidedi::Exceptions::InvalidSchemaError) do |error|
      expect(error.message).to match(/overlapping/)
      expect(error.message).to match(/ValueBased/)
    end
  end
end
