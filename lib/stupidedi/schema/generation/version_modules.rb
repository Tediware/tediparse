# frozen_string_literal: true

module Stupidedi
  module Schema
    module Generation
      # Maps 6-digit ASC X12 release codes to the Ruby module names used by the
      # generated grammar (e.g. "005010" => "FiftyTen"). This is the canonical
      # list of releases the generator supports.
      VERSION_MODULES = {
        "003060" => "ThirtySixty",
        "004010" => "FortyTen",
        "004060" => "FortySixty",
        "005010" => "FiftyTen",
        "006010" => "SixtyTen",
        "007010" => "SeventyTen",
        "008010" => "EightyTen"
      }.freeze

      # Maps X12 requirement designators to Stupidedi ElementReq names.
      # Note: Conditional -> Relational and NotUsed -> Optional are deliberate.
      REQUIREMENT_MAP = {
        "Mandatory"   => "Mandatory",
        "Optional"    => "Optional",
        "Conditional" => "Relational",
        "NotUsed"     => "Optional"
      }.freeze

      # A valid output namespace is a single Ruby constant name (e.g. "Edi").
      # Nested namespaces ("Acme::Grammars") are not supported: the generated
      # code uses `module <namespace>` directly, which only works for a single
      # top-level constant.
      NAMESPACE_FORMAT = /\A[A-Z]\w*\z/
    end
  end
end
