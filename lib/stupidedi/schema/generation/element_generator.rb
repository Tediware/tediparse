# frozen_string_literal: true

module Stupidedi
  module Schema
    module Generation
      # Generates element_defs.rb for a release: every simple and composite
      # element definition. ID elements with code lists emit a CodeList; control
      # /separator elements (e.g. I15, I65) that carry no x12_type are emitted
      # with the Separator type so #separator? is true.
      class ElementGenerator
        include Support

        TYPE_MAPPING = {
          "AN" => :AN,
          "ID" => :ID,
          "DT" => :DT,
          "TM" => :TM,
          "R"  => :R,
          "N0" => :Nn,
          "N1" => :Nn,
          "N2" => :Nn,
          "N4" => :Nn,
          "N6" => :Nn,
          "N"  => :Nn,
          "B"  => :AN # Binary as AN
        }.freeze

        def initialize(release, namespace: "Edi")
          @release = release
          @namespace = namespace
        end

        def generate
          validate_release!
          build_ruby_content
        end

        def output_path
          "#{namespace_path}/#{underscore(version_module)}/element_defs.rb"
        end

        private

        attr_reader :release

        def release_code
          release.code
        end

        def build_ruby_content
          lines = []
          lines << 'require "tediparse"'
          lines << "module #{namespace}"
          lines << "  module #{version_module}"
          lines << "    module ElementDefs"
          lines << "      t = #{namespace}::#{version_module}::ElementTypes"
          lines << "      r = #{namespace}::#{version_module}::ElementReqs"
          lines << "      s = Stupidedi::Schema"
          lines << ""
          lines << build_simple_element_definitions
          lines << ""
          lines << "#{indent(3)}# Composite Elements"
          lines << build_composite_element_definitions
          lines << "    end"
          lines << "  end"
          lines << "end"
          lines.join("\n") + "\n"
        end

        def build_simple_element_definitions
          elements = release.elements.reject(&:is_composite).reject { |e| blank_type?(e) }

          sorted_elements = sort_elements(elements)
          simple_defs = sorted_elements.map { |element| generate_element_def(element) }

          # Add special control/separator elements (e.g. I15, I65, I69) that have
          # no x12_type but are referenced by segments in this release.
          control_defs = control_elements.map { |element| generate_control_element_def(element) }

          (simple_defs + control_defs).join("\n")
        end

        def build_composite_element_definitions
          composites = release.elements.select(&:is_composite)

          sorted_composites = sort_elements(composites)
          sorted_composites.map { |composite| generate_composite_def(composite) }.join("\n")
        end

        # Simple elements with no x12_type that are referenced by some segment's
        # element use (the ISA control/separator elements).
        def control_elements
          referenced_codes = release.segments
            .flat_map(&:element_uses)
            .map(&:element)
            .select { |el| !el.is_composite && blank_type?(el) }
            .map(&:code)
            .uniq

          release.elements.select do |el|
            !el.is_composite && blank_type?(el) && referenced_codes.include?(el.code)
          end
        end

        def blank_type?(element)
          element.x12_type.nil? || element.x12_type.empty?
        end

        def sort_elements(elements)
          # Sort numeric codes numerically, then alphanumeric codes alphabetically
          elements.sort_by do |element|
            code = element.code
            if code.match?(/^\d+$/)
              [0, code.to_i, ""]
            else
              [1, 0, code]
            end
          end
        end

        def generate_element_def(element)
          stupidedi_type = TYPE_MAPPING.fetch(element.x12_type) do
            raise ArgumentError, "Unknown x12_type: #{element.x12_type} for element #{element.code}"
          end

          if element.x12_type == "ID" && element.element_codes.any?
            generate_id_element(element, stupidedi_type)
          elsif stupidedi_type == :Nn
            generate_numeric_element(element, stupidedi_type)
          else
            generate_simple_element(element, stupidedi_type)
          end
        end

        def generate_composite_def(composite)
          component_uses = composite.component_uses.sort_by(&:position)

          lines = []
          lines << "#{indent(3)}#{composite.code} ||= s::CompositeElementDef.build(:#{composite.code},"
          lines << "#{indent(4)}#{escape_string(composite.name)},"
          lines << "#{indent(4)}#{escape_string(composite.description || '')},"

          component_uses.each_with_index do |component_use, index|
            is_last = index == component_uses.length - 1
            lines << generate_component_use(component_use, is_last: is_last)
          end

          lines << "#{indent(3)})"
          lines.join("\n")
        end

        def generate_component_use(component_use, is_last:)
          element = component_use.element
          requirement = format_requirement(component_use.requirement)
          trailing_comma = is_last ? "" : ","

          "#{indent(4)}E#{element.code}.component_use(#{requirement})#{trailing_comma}"
        end

        def generate_simple_element(element, stupidedi_type)
          max_length = element.max_length || element.min_length
          "#{indent(3)}E#{element.code} ||= t::#{stupidedi_type}.new(:E#{element.code}, #{escape_string(element.name)}, #{element.min_length}, #{max_length})"
        end

        # Separator elements (I15, I65) have no x12_type - use Tediparse's
        # Separator type so that #separator? returns true and the writer excludes
        # them from data character checks.
        def generate_control_element_def(element)
          max_length = element.max_length || element.min_length
          "#{indent(3)}E#{element.code} ||= Stupidedi::Interchanges::ElementTypes::Separator.new(:E#{element.code}, #{escape_string(element.name)}, #{element.min_length}, #{max_length})"
        end

        def generate_numeric_element(element, stupidedi_type)
          max_length = element.max_length || element.min_length
          digits = extract_decimal_places(element)
          "#{indent(3)}E#{element.code} ||= t::#{stupidedi_type}.new(:E#{element.code}, #{escape_string(element.name)}, #{element.min_length}, #{max_length}, #{digits})"
        end

        def generate_id_element(element, stupidedi_type)
          codes = element.element_codes.sort_by { |c| [c.paragraph, c.code] }

          return generate_simple_element(element, stupidedi_type) if codes.empty?

          max_length = element.max_length || element.min_length
          lines = []
          lines << "#{indent(3)}E#{element.code} ||= t::#{stupidedi_type}.new(:E#{element.code}, #{escape_string(element.name)}, #{element.min_length}, #{max_length},"
          lines << "#{indent(4)}s::CodeList.build("

          code_lines = codes.map do |code|
            "#{indent(5)}#{escape_string(code.code)} => #{escape_string(code.name)}"
          end
          lines << code_lines.join(",\n") + "))"

          lines.join("\n")
        end

        def extract_decimal_places(element)
          case element.x12_type
          when "N0", "N" then 0
          when "N1" then 1
          when "N2" then 2
          when "N4" then 4
          when "N6" then 6
          else
            element.digits || 0
          end
        end
      end
    end
  end
end
