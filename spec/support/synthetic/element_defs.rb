# frozen_string_literal: true
#
# Synthetic element definitions.
#
# These are NOT X12 elements. They are deliberately-generic placeholders used
# by the test grammar so the parser/reader/writer engine can be exercised
# without bundling any licensed X12 grammar content. Element ids start with
# `SY_` (envelope) or `SD_` (data) to keep them visually distinct from any
# real X12 designator (E143, I11, etc).
#
module Synthetic
  module ElementDefs
    s = Stupidedi::Schema
    t = Stupidedi::Versions::Common::ElementTypes
    c = Stupidedi::Interchanges::ElementTypes
    r = Stupidedi::Versions::Common::ElementReqs

    # ---------------------------------------------------------------------------
    # Envelope elements (used by synthetic ISA / GS / TA1 / IEA / GE segments)
    # ---------------------------------------------------------------------------
    SY_AUTH_QUAL = t::ID.new(:SY_AUTH_QUAL, "Authorization Qualifier", 2, 2,
      s::CodeList.build("00" => "No authorization present"))

    SY_AUTH_INFO = c::SpecialAN.new(:SY_AUTH_INFO, "Authorization Information", 10, 10)

    SY_SEC_QUAL = t::ID.new(:SY_SEC_QUAL, "Security Qualifier", 2, 2,
      s::CodeList.build("00" => "No security information"))

    SY_SEC_INFO = c::SpecialAN.new(:SY_SEC_INFO, "Security Information", 10, 10)

    SY_ID_QUAL = t::ID.new(:SY_ID_QUAL, "Identifier Qualifier", 2, 2,
      s::CodeList.build("ZZ" => "Mutually defined"))

    SY_PARTY_ID = c::SpecialAN.new(:SY_PARTY_ID, "Party Identifier", 15, 15)

    SY_DATE6 = t::DT.new(:SY_DATE6, "Date (YYMMDD)",   6, 6)
    SY_DATE8 = t::DT.new(:SY_DATE8, "Date (YYYYMMDD)", 8, 8)
    SY_TIME  = t::TM.new(:SY_TIME,  "Time (HHMM)",     4, 4)

    SY_REP_SEP = c::Separator.new(:SY_REP_SEP, "Repetition Separator", 1, 1)
    SY_COMP_SEP = c::Separator.new(:SY_COMP_SEP, "Component Separator", 1, 1)

    SY_VERSION = t::ID.new(:SY_VERSION, "Interchange / Group Version", 5, 6,
      s::CodeList.build("DEMO01" => "Synthetic demo grammar"))

    # 9/9 control number (used by ISA13 / IEA02 — must round-trip with leading zeros)
    SY_ISA_CTRL = t::Nn.new(:SY_ISA_CTRL, "ISA/IEA Control Number", 9, 9, 0)
    # Variable-width control number, used by GS06 / GE02 / TA1. (ST02 uses SY_ST_CTRL instead.)
    SY_CTRL_NUM = t::Nn.new(:SY_CTRL_NUM, "Control Number", 1, 9, 0)
    SY_ACK_REQ  = t::ID.new(:SY_ACK_REQ,  "Acknowledgement Requested", 1, 1,
      s::CodeList.build("0" => "No", "1" => "Yes"))
    SY_USAGE    = t::ID.new(:SY_USAGE, "Usage Indicator", 1, 1,
      s::CodeList.build("T" => "Test", "P" => "Production"))

    SY_GS_SENDER   = t::AN.new(:SY_GS_SENDER,   "Sender Code",   2, 15)
    SY_GS_RECEIVER = t::AN.new(:SY_GS_RECEIVER, "Receiver Code", 2, 15)
    SY_GS_FNCID    = t::ID.new(:SY_GS_FNCID, "Functional Identifier", 2, 2,
      s::CodeList.build("ZZ" => "Mutually defined"))
    SY_GS_AGENCY   = t::ID.new(:SY_GS_AGENCY, "Responsible Agency", 1, 2,
      s::CodeList.build("X" => "ASC X12"))
    SY_GS_COUNT    = t::Nn.new(:SY_GS_COUNT, "Number of Transaction Sets", 1, 6, 0)

    SY_TA1_NOTE = t::ID.new(:SY_TA1_NOTE, "Acknowledgement Note", 1, 3,
      s::CodeList.build("000" => "OK", "001" => "Error"))
    SY_TA1_ACK = t::ID.new(:SY_TA1_ACK, "Acknowledgement Code", 1, 1,
      s::CodeList.build("A" => "Accepted", "E" => "Errors noted", "R" => "Rejected"))

    SY_SEG_COUNT = t::Nn.new(:SY_SEG_COUNT, "Segment Count", 1, 10, 0)

    # ST elements
    SY_ST_ID   = t::AN.new(:SY_ST_ID,   "Transaction Set Identifier", 3, 3)
    SY_ST_CTRL = t::AN.new(:SY_ST_CTRL, "Transaction Set Control Number", 4, 9)

    # ---------------------------------------------------------------------------
    # Data elements (used by synthetic body segments)
    # ---------------------------------------------------------------------------

    # Qualifier with a small enumerated code list — used by loop openers to
    # discriminate sibling loops (the typical "qualifier element" pattern).
    SD_KIND = t::ID.new(:SD_KIND, "Synthetic Kind Qualifier", 1, 2,
      s::CodeList.build(
        "P"  => "Primary",
        "O"  => "Override",
        "S"  => "Secondary",
        "AB" => "Alpha",
        "CD" => "Beta"))

    SD_TEXT  = t::AN.new(:SD_TEXT, "Synthetic Free Text", 1, 60)
    SD_COUNT = t::Nn.new(:SD_COUNT, "Synthetic Count",    1, 6, 0)
    SD_AMT   = t::R.new(:SD_AMT,   "Synthetic Amount",   1, 12)
    SD_DATE  = t::DT.new(:SD_DATE, "Synthetic Date",     8, 8)

    # Composite element (two components, second optional). Exercises composite
    # parsing/writing in round-trip tests.
    SD_COMPOSITE = s::CompositeElementDef.build(:SD_COMPOSITE, "Synthetic Composite", "",
      SD_KIND.component_use(r::Mandatory),
      SD_TEXT.component_use(r::Optional))
  end
end
