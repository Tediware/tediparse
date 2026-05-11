# frozen_string_literal: true
require_relative "segment_defs"

#
# Synthetic demo transaction set.
#
# Designed to exercise the engine's interesting code paths in one transmission:
#
#   * Header table with envelope (ST) + optional segment (HH).
#   * Detail table with two qualifier-discriminated sibling loops (LO/IT) —
#     the same loop opener `:LO` segment is used for both, with the first
#     element `SD_KIND` restricted to disjoint code sets, so the parser must
#     choose by element value (the `ValueBased` ConstraintTable path).
#   * Interleaved trailing segment (`FT`) between the two loops in the
#     detail table — the SO317-style pattern.
#   * A third loop containing two structurally-identical sibling `:NX` slots
#     with no qualifier — the tediparse-04 duplicate-slot shape.
#   * Optional `IT` segment whose `SD_AMT` is paired to `SD_COUNT` via the
#     `P` syntax note (if any element specified is present, all must be).
#   * Summary table with `TT` (optional) and `SE` (mandatory).
#
# Registered as: (gs08="DEMO01", gs01="ZZ", st01="100").
#
module Synthetic
  b = Stupidedi::TransactionSets::Builder
  d = Stupidedi::Schema
  r = Stupidedi::Versions::Common::ElementReqs
  q = Stupidedi::Versions::Common::SegmentReqs
  s = Synthetic::SegmentDefs

  Demo = b.build("ZZ", "100", "Synthetic Demo Transaction Set",
    d::TableDef.header("Heading",
      s::ST.use(100, q::Mandatory, d::RepeatCount.bounded(1)),
      s::HH.use(200, q::Optional,  d::RepeatCount.bounded(1))),

    d::TableDef.detail("Detail",
      # Loop 1: primary block, opener element SD_KIND must equal "P"
      d::LoopDef.build("LO-PRIMARY", d::RepeatCount.bounded(1),
        b::Segment(300, s::LO, "Primary Loop Opener", q::Optional, d::RepeatCount.bounded(1),
          b::Element(r::Mandatory, "Kind", b::Values("P")),
          b::Element(r::Optional,  "Description")),
        # IT carries a P syntax note (declared on its SegmentDef) pairing
        # SD_COUNT and SD_AMT — if either is present, both must be.
        s::IT.use(400, q::Optional, d::RepeatCount.unbounded)),

      # Interleaved standalone segment between two loops — SO317-style.
      s::FT.use(500, q::Optional, d::RepeatCount.bounded(1)),

      # Loop 2: override block, opener element SD_KIND must equal "O"
      d::LoopDef.build("LO-OVERRIDE", d::RepeatCount.bounded(1),
        b::Segment(600, s::LO, "Override Loop Opener", q::Optional, d::RepeatCount.bounded(1),
          b::Element(r::Mandatory, "Kind", b::Values("O")),
          b::Element(r::Optional,  "Description")),
        s::IT.use(700, q::Optional, d::RepeatCount.unbounded)),

      # Loop 3: duplicate-slot probe (tediparse-04 shape).
      # Two `NX` segment uses inside one loop, both with the same SegmentDef
      # and no discriminating element. Opener is LO with SD_KIND="S".
      d::LoopDef.build("NX-PAIR", d::RepeatCount.bounded(1),
        b::Segment(800, s::LO, "Secondary Loop Opener", q::Optional, d::RepeatCount.bounded(1),
          b::Element(r::Mandatory, "Kind", b::Values("S")),
          b::Element(r::Optional,  "Description")),
        s::NX.use(900,  q::Optional, d::RepeatCount.bounded(1)),
        s::NX.use(1000, q::Optional, d::RepeatCount.bounded(1)))),

    d::TableDef.summary("Summary",
      s::TT.use(1100, q::Optional,  d::RepeatCount.bounded(1)),
      s::SE.use(1200, q::Mandatory, d::RepeatCount.bounded(1))))
end
