# frozen_string_literal: true
require_relative "segment_defs"

#
# Synthetic transaction set deliberately constructed to be ambiguous.
#
# Two `LO` loop openers with overlapping allowed_values on element 1 — both
# permit "P" — so a single "LO*P*..." opener cannot be assigned to one loop
# unambiguously. The Ambiguity validator should flag this.
#
# Registered as: (gs08="DEMO01", gs01="ZZ", st01="999").
#
module Synthetic
  b = Stupidedi::TransactionSets::Builder
  d = Stupidedi::Schema
  r = Stupidedi::Versions::Common::ElementReqs
  q = Stupidedi::Versions::Common::SegmentReqs
  s = Synthetic::SegmentDefs

  AmbiguousDemo = b.build("ZZ", "999", "Synthetic Ambiguous Demo",
    d::TableDef.header("Heading",
      s::ST.use(100, q::Mandatory, d::RepeatCount.bounded(1))),

    d::TableDef.detail("Detail",
      # Two sibling loops whose openers sit at the SAME position (200) AND
      # share the SD_KIND code "P". When an `LO*P*…` segment arrives, the
      # parser cannot deterministically choose between them — the
      # ValueBased ConstraintTable path runs and Ambiguity#audit must flag
      # this as a schema error.
      d::LoopDef.build("LO-AMBIG-A", d::RepeatCount.bounded(1),
        b::Segment(200, s::LO, "Ambig Opener A", q::Mandatory, d::RepeatCount.bounded(1),
          b::Element(r::Mandatory, "Kind", b::Values("P", "S")),
          b::Element(r::Optional,  "Description"))),
      d::LoopDef.build("LO-AMBIG-B", d::RepeatCount.bounded(1),
        b::Segment(200, s::LO, "Ambig Opener B", q::Mandatory, d::RepeatCount.bounded(1),
          b::Element(r::Mandatory, "Kind", b::Values("P", "O")),
          b::Element(r::Optional,  "Description")))),

    d::TableDef.summary("Summary",
      s::SE.use(400, q::Mandatory, d::RepeatCount.bounded(1))))
end
