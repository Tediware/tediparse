# frozen_string_literal: true

module Stupidedi
  module Schema
    module Generation
      # Generates segment_defs.rb for a release: every segment definition with
      # its ordered element uses and syntax notes. With include_control_segments:
      # true it also emits ISA/IEA/GS/GE/TA1.
      class SegmentGenerator
        include Support

        SYNTAX_NOTE_MAP = {
          "paired"           => "P",
          "required"         => "R",
          "conditional"      => "C",
          "excluded"         => "E",
          "list_conditional" => "L"
        }.freeze

        # Interchange control segments - included when include_control_segments: true
        CONTROL_SEGMENTS = %w[ISA IEA GS GE TA1].freeze

        def initialize(release, include_control_segments: false, namespace: "Edi")
          @release = release
          @include_control_segments = include_control_segments
          @namespace = namespace
        end

        def generate
          validate_release!
          build_ruby_content
        end

        def output_path
          "#{namespace_path}/#{underscore(version_module)}/segment_defs.rb"
        end

        private

        attr_reader :release

        def release_code
          release.code
        end

        def include_control_segments?
          @include_control_segments
        end

        def build_ruby_content
          lines = []
          lines << 'require "tediparse"'
          lines << "module #{namespace}"
          lines << "  module #{version_module}"
          lines << "    module SegmentDefs"
          lines << "      s = Stupidedi::Schema"
          lines << "      e = #{namespace}::#{version_module}::ElementDefs"
          lines << "      r = #{namespace}::#{version_module}::ElementReqs"
          lines << ""
          lines << build_segment_definitions
          lines << "    end"
          lines << "  end"
          lines << "end"
          lines.join("\n") + "\n"
        end

        def build_segment_definitions
          segments = release.segments.sort_by(&:code)
          segments = segments.reject { |seg| CONTROL_SEGMENTS.include?(seg.code) } unless include_control_segments?

          segments.map { |segment| generate_segment_def(segment) }.join("\n")
        end

        def generate_segment_def(segment)
          lines = []
          lines << "#{indent(3)}#{segment.code} ||= s::SegmentDef.build(:#{segment.code},"
          lines << "#{indent(4)}#{escape_string(segment.name)},"
          lines << "#{indent(4)}#{escape_string(segment.purpose || '')},"

          element_uses = segment.element_uses.sort_by(&:position)
          syntax_notes = segment.syntax_notes.to_a

          element_uses.each_with_index do |element_use, index|
            is_last = index == element_uses.length - 1 && syntax_notes.empty?
            lines << generate_element_use(element_use, is_last: is_last)
          end

          syntax_notes.each_with_index do |syntax_note, index|
            is_last = index == syntax_notes.length - 1
            lines << generate_syntax_note(syntax_note, is_last: is_last)
          end

          lines << "#{indent(3)})"
          lines.join("\n")
        end

        def generate_element_use(element_use, is_last:)
          element = element_use.element
          requirement = format_requirement(element_use.requirement)
          trailing_comma = is_last ? "" : ","

          comment = " # Min #{element.min_length}/Max #{element.max_length}"

          # Composite elements don't have the E prefix
          element_ref = element.is_composite ? element.code : "E#{element.code}"

          "#{indent(4)}e::#{element_ref}.simple_use(#{requirement}, s::RepeatCount.bounded(1))#{trailing_comma}#{comment}"
        end

        def generate_syntax_note(syntax_note, is_last:)
          note_class = SYNTAX_NOTE_MAP.fetch(syntax_note.condition_type) do
            raise ArgumentError, "Unknown condition_type: #{syntax_note.condition_type}"
          end

          positions = syntax_note.element_positions
          positions_str = positions.join(", ")
          trailing_comma = is_last ? "" : ","

          "#{indent(4)}#{namespace}::#{version_module}::SyntaxNotes::#{note_class}.build(#{positions_str})#{trailing_comma}"
        end
      end
    end
  end
end
