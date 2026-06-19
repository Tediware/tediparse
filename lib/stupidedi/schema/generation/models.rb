# frozen_string_literal: true

module Stupidedi
  module Schema
    module Generation
      # Plain-Ruby value objects mirroring the shape of the X12 standard data.
      #
      # These are the seam between the input reader (Layer A) and the grammar
      # generators (Layer B): the FlatFileReader populates them, the generators
      # consume them. They carry no database or persistence concerns. Any source
      # that builds objects responding to these methods can drive the generators.
      #
      # The reader always populates every field (collections default to []), so
      # the structs need no custom initializers — keeping them compatible across
      # the supported Ruby range (2.6+).
      module Models
        # A whole X12 release: its elements (simple + composite), its segments,
        # and its transaction sets.
        Release = Struct.new(:code, :elements, :segments, :transaction_sets, keyword_init: true)

        # A data element or composite (distinguished by #is_composite).
        # Simple elements carry x12_type/min_length/max_length/digits and, for
        # ID elements, element_codes. Composites carry component_uses.
        Element = Struct.new(
          :code, :name, :description, :x12_type, :is_composite,
          :min_length, :max_length, :digits, :element_codes, :component_uses,
          keyword_init: true
        )

        # A single code-list entry for an ID element.
        ElementCode = Struct.new(:code, :name, :paragraph, :partition, keyword_init: true)

        # A component element used within a composite definition.
        ComponentUse = Struct.new(:position, :requirement, :element, keyword_init: true)

        # A segment definition with its ordered element uses and syntax notes.
        Segment = Struct.new(:code, :name, :purpose, :element_uses, :syntax_notes, keyword_init: true)

        # An element referenced from a specific position within a segment.
        ElementUse = Struct.new(:position, :requirement, :element, keyword_init: true)

        # A segment syntax rule (P/R/C/E/L) over a set of element positions.
        SyntaxNote = Struct.new(:condition_type, :element_positions, :description, keyword_init: true)

        # A transaction set: its functional group id, code, name, owning release,
        # and ordered table definitions.
        TransactionSet = Struct.new(:code, :func_group, :name, :release, :table_definitions, keyword_init: true)

        # A heading/detail/summary table. #area is the lowercase enum name
        # ("heading"/"detail"/"summary"); #name is the display name. #children is
        # a mixed, ordered list of SegmentUse and LoopDefinition.
        TableDefinition = Struct.new(:area, :name, :position, :children, keyword_init: true) do
          def ordered_children
            # Index tiebreaker keeps ordering deterministic if two children ever
            # share a position (Ruby's sort_by is not stable).
            children.each_with_index.sort_by { |child, i| [child.position, i] }.map(&:first)
          end
        end

        # A loop within a table or another loop. #children nests recursively.
        # #max_reps is nil for unbounded.
        LoopDefinition = Struct.new(:identifier, :max_reps, :position, :children, keyword_init: true) do
          def ordered_children
            children.each_with_index.sort_by { |child, i| [child.position, i] }.map(&:first)
          end

          def segment_use?
            false
          end
        end

        # A segment referenced from a specific position within a table or loop.
        # #x12_sequence is the (string) sequence number from the standard, which
        # takes precedence over #position when present.
        SegmentUse = Struct.new(:segment, :x12_sequence, :position, :requirement, :max_reps, keyword_init: true) do
          def segment_use?
            true
          end
        end
      end
    end
  end
end
