# frozen_string_literal: true
require_relative "element_defs"

#
# Synthetic segment definitions.
#
# The envelope segments (ISA / IEA / GS / GE / TA1 / ST / SE) reuse the X12
# segment IDs because the parser state machine hard-codes those identifiers
# in its bootstrap (see lib/stupidedi/parser/states/initial_state.rb and
# friends). The plan treats envelope segment IDs as protocol vocabulary, not
# licensed grammar content.
#
# The body segments (HH / LO / IT / TT / FT) use two-letter placeholder IDs
# that intentionally do NOT appear in any X12 transaction set.
#
module Synthetic
  module SegmentDefs
    s = Stupidedi::Schema
    e = Synthetic::ElementDefs
    r = Stupidedi::Versions::Common::ElementReqs

    # ---------------------------------------------------------------------------
    # Envelope segments
    # ---------------------------------------------------------------------------
    ISA = s::SegmentDef.build(:ISA, "Interchange Control Header", "",
      e::SY_AUTH_QUAL.simple_use(r::Mandatory, s::RepeatCount.bounded(1)),
      e::SY_AUTH_INFO.simple_use(r::Optional,  s::RepeatCount.bounded(1)),
      e::SY_SEC_QUAL .simple_use(r::Mandatory, s::RepeatCount.bounded(1)),
      e::SY_SEC_INFO .simple_use(r::Optional,  s::RepeatCount.bounded(1)),
      e::SY_ID_QUAL  .simple_use(r::Mandatory, s::RepeatCount.bounded(1)),
      e::SY_PARTY_ID .simple_use(r::Mandatory, s::RepeatCount.bounded(1)),
      e::SY_ID_QUAL  .simple_use(r::Mandatory, s::RepeatCount.bounded(1)),
      e::SY_PARTY_ID .simple_use(r::Mandatory, s::RepeatCount.bounded(1)),
      e::SY_DATE6    .simple_use(r::Mandatory, s::RepeatCount.bounded(1)),
      e::SY_TIME     .simple_use(r::Mandatory, s::RepeatCount.bounded(1)),
      e::SY_REP_SEP    .simple_use(r::Mandatory, s::RepeatCount.bounded(1)),
      e::SY_ISA_VERSION.simple_use(r::Mandatory, s::RepeatCount.bounded(1)),
      e::SY_ISA_CTRL   .simple_use(r::Mandatory, s::RepeatCount.bounded(1)),
      e::SY_ACK_REQ  .simple_use(r::Mandatory, s::RepeatCount.bounded(1)),
      e::SY_USAGE    .simple_use(r::Mandatory, s::RepeatCount.bounded(1)),
      e::SY_COMP_SEP .simple_use(r::Mandatory, s::RepeatCount.bounded(1)))

    IEA = s::SegmentDef.build(:IEA, "Interchange Control Trailer", "",
      e::SY_GS_COUNT.simple_use(r::Mandatory, s::RepeatCount.bounded(1)),
      e::SY_ISA_CTRL.simple_use(r::Mandatory, s::RepeatCount.bounded(1)))

    TA1 = s::SegmentDef.build(:TA1, "Interchange Acknowledgement", "",
      e::SY_CTRL_NUM .simple_use(r::Mandatory, s::RepeatCount.bounded(1)),
      e::SY_DATE6    .simple_use(r::Mandatory, s::RepeatCount.bounded(1)),
      e::SY_TIME     .simple_use(r::Mandatory, s::RepeatCount.bounded(1)),
      e::SY_TA1_ACK  .simple_use(r::Mandatory, s::RepeatCount.bounded(1)),
      e::SY_TA1_NOTE .simple_use(r::Mandatory, s::RepeatCount.bounded(1)))

    GS = s::SegmentDef.build(:GS, "Functional Group Header", "",
      e::SY_GS_FNCID   .simple_use(r::Mandatory, s::RepeatCount.bounded(1)),
      e::SY_GS_SENDER  .simple_use(r::Mandatory, s::RepeatCount.bounded(1)),
      e::SY_GS_RECEIVER.simple_use(r::Mandatory, s::RepeatCount.bounded(1)),
      e::SY_DATE8      .simple_use(r::Mandatory, s::RepeatCount.bounded(1)),
      e::SY_TIME       .simple_use(r::Mandatory, s::RepeatCount.bounded(1)),
      e::SY_CTRL_NUM   .simple_use(r::Mandatory, s::RepeatCount.bounded(1)),
      e::SY_GS_AGENCY  .simple_use(r::Mandatory, s::RepeatCount.bounded(1)),
      e::SY_GS_VERSION .simple_use(r::Mandatory, s::RepeatCount.bounded(1)))

    GE = s::SegmentDef.build(:GE, "Functional Group Trailer", "",
      e::SY_GS_COUNT.simple_use(r::Mandatory, s::RepeatCount.bounded(1)),
      e::SY_CTRL_NUM.simple_use(r::Mandatory, s::RepeatCount.bounded(1)))

    # Two-element ST mirrors the basic X12 ST wire shape. There is a parallel
    # 3-element ST in `Definitions::SegmentDefs::ST` (see spec/support/
    # definitions.rb) that the wide-surface specs see via
    # `Definitions::FunctionalGroupDelegator#segment_dict`. The two
    # definitions are intentionally distinct: this one is what an unwrapped
    # `Synthetic.config` exposes; that one is what specs which wrap with the
    # delegator see. If you change one shape, consider the other.
    ST = s::SegmentDef.build(:ST, "Transaction Set Header", "",
      e::SY_ST_ID  .simple_use(r::Mandatory, s::RepeatCount.bounded(1)),
      e::SY_ST_CTRL.simple_use(r::Mandatory, s::RepeatCount.bounded(1)))

    SE = s::SegmentDef.build(:SE, "Transaction Set Trailer", "",
      e::SY_SEG_COUNT.simple_use(r::Mandatory, s::RepeatCount.bounded(1)),
      e::SY_ST_CTRL  .simple_use(r::Mandatory, s::RepeatCount.bounded(1)))

    # ---------------------------------------------------------------------------
    # Body segments — placeholder IDs not used by any X12 transaction set.
    # ---------------------------------------------------------------------------

    # HH — Header / Heading. Single free-form field; sits in the header table.
    HH = s::SegmentDef.build(:HH, "Heading", "",
      e::SD_TEXT.simple_use(r::Mandatory, s::RepeatCount.bounded(1)))

    # LO — Loop Opener. First element is the kind-qualifier (`SD_KIND`), so
    # two LO-opened loops can be discriminated by element value the way an
    # X12 N1 loop is discriminated by N101.
    LO = s::SegmentDef.build(:LO, "Loop Opener", "",
      e::SD_KIND.simple_use(r::Mandatory, s::RepeatCount.bounded(1)),
      e::SD_TEXT.simple_use(r::Optional,  s::RepeatCount.bounded(1)))

    # IT — Item Detail. Carries a composite element and a numeric, plus an
    # optional amount. The P syntax note pairs SD_COUNT (element 2) and
    # SD_AMT (element 3): if either is present, both must be present.
    IT = s::SegmentDef.build(:IT, "Item Detail", "",
      e::SD_COMPOSITE.simple_use(r::Mandatory, s::RepeatCount.bounded(1)),
      e::SD_COUNT.simple_use(r::Optional, s::RepeatCount.bounded(1)),
      e::SD_AMT  .simple_use(r::Optional, s::RepeatCount.bounded(1)),
      Stupidedi::Versions::Common::SyntaxNotes::P.build(2, 3))

    # TT — Transaction Totals. Sits in summary table before SE.
    TT = s::SegmentDef.build(:TT, "Transaction Totals", "",
      e::SD_COUNT.simple_use(r::Mandatory, s::RepeatCount.bounded(1)),
      e::SD_AMT  .simple_use(r::Optional,  s::RepeatCount.bounded(1)))

    # FT — Footer / interleaved trailing detail. Carries text only; lives
    # between two loops in the detail table to exercise the SO317-style
    # interleaved-segments-and-loops pattern.
    FT = s::SegmentDef.build(:FT, "Footer", "",
      e::SD_TEXT.simple_use(r::Mandatory, s::RepeatCount.bounded(1)),
      e::SD_DATE.simple_use(r::Optional,  s::RepeatCount.bounded(1)))

    # NX — duplicate-slot probe. Two `NX` SegmentUses inside the same loop,
    # with no qualifier element, exercise the tediparse-04 fix (preference
    # for the earlier slot when no later-slot opener has been seen).
    NX = s::SegmentDef.build(:NX, "Duplicate-Slot Probe", "",
      e::SD_TEXT.simple_use(r::Mandatory, s::RepeatCount.bounded(1)))
  end
end
