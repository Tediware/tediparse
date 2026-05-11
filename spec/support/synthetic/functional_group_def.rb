# frozen_string_literal: true
require_relative "segment_defs"

#
# Synthetic FunctionalGroupDef, registered under version "DEMO01".
#
# Modelled on lib/stupidedi/versions/005010/functional_group_def.rb.
#
module Synthetic
  s = Stupidedi::Schema
  r = Stupidedi::Versions::Common::ElementReqs

  FunctionalGroupDef = Class.new(Stupidedi::Schema::FunctionalGroupDef) do
    def empty
      Stupidedi::Values::FunctionalGroupVal.new(self, [])
    end

    def segment_dict
      Synthetic::SegmentDefs
    end
  end.new("DEMO01",
    [ Synthetic::SegmentDefs::GS.use(1, r::Mandatory, s::RepeatCount.bounded(1)) ],
    [ Synthetic::SegmentDefs::GE.use(2, r::Mandatory, s::RepeatCount.bounded(1)) ])
end
