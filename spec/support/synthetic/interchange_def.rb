# frozen_string_literal: true
require_relative "segment_defs"

#
# Synthetic InterchangeDef, registered under version "DEMO01".
#
# Modelled on lib/stupidedi/interchanges/00501/interchange_def.rb in the
# pre-x12-removal git tag (the upstream X12 content tree, removed from this
# branch). The methods `empty`, `segment_dict`, `separators`, and
# `replace_separators` are required by the parser state machine and are not
# part of the abstract base class.
#
module Synthetic
  s = Stupidedi::Schema
  r = Stupidedi::Versions::Common::ElementReqs

  InterchangeDef = Class.new(Stupidedi::Schema::InterchangeDef) do
    def empty(separators)
      Stupidedi::Values::InterchangeVal.new(self, [], separators)
    end

    def segment_dict
      Synthetic::SegmentDefs
    end

    def separators(isa)
      Stupidedi::Reader::Separators.new(
        isa.element(16).to_s,
        isa.element(11).to_s,
        nil, nil)
    end

    def replace_separators(isa, separators)
      isa.copy \
        :separators => separators,
        :children   => [
          isa.element(1),
          isa.element(2),
          isa.element(3),
          isa.element(4),
          isa.element(5),
          isa.element(6),
          isa.element(7),
          isa.element(8),
          isa.element(9),
          isa.element(10),
          isa.element(11).copy(:value => separators.repetition),
          isa.element(12),
          isa.element(13),
          isa.element(14),
          isa.element(15),
          isa.element(16).copy(:value => separators.component)]
    end
  end.new("DEMO01",
    [ Synthetic::SegmentDefs::ISA.use(1, r::Mandatory, s::RepeatCount.bounded(1)),
      Synthetic::SegmentDefs::TA1.use(4, r::Optional,  s::RepeatCount.unbounded) ],
    [ Synthetic::SegmentDefs::IEA.use(5, r::Mandatory, s::RepeatCount.bounded(1)) ])
end
