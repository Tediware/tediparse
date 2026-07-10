# frozen_string_literal: true

require "csv"

module Stupidedi
  module Schema
    module Generation
      # Reads ASC X12 Table Data flat files (the official .TXT distribution, CSV
      # despite the extension, ISO-8859-1 encoded) and builds the in-memory
      # Models tree the generators consume. This is Layer A - the inverse of the
      # Tediware x12:import importer, with no database.
      #
      #   release = FlatFileReader.read("vendor/x12/table_data/005010", "005010")
      #
      # Files consumed: ELEHEAD/ELEDETL (simple elements), COMHEAD/COMDETL
      # (composites), SEGHEAD/SEGDETL (segments + element uses), SETHEAD/SETDETL
      # (transaction sets + structure), FREEFORM (code lists + syntax notes).
      class FlatFileReader
        ENCODING = "ISO-8859-1:UTF-8"

        def self.read(dir, release_code)
          new(dir, release_code).read
        end

        def initialize(dir, release_code)
          @dir = dir
          @release_code = release_code
          @elements_by_code = {}
          @segments_by_code = {}
          @transaction_sets_by_code = {}
        end

        def read
          read_elements
          read_composites
          read_segments
          read_element_uses
          read_component_uses
          read_transaction_sets
          read_freeform

          release = Models::Release.new(
            code: @release_code,
            elements: @elements_by_code.values,
            segments: @segments_by_code.values,
            transaction_sets: @transaction_sets_by_code.values
          )
          release.transaction_sets.each { |ts| ts.release = release }
          release
        end

        private

        attr_reader :dir, :release_code

        # ELEHEAD.TXT (code, name) + ELEDETL.TXT (code, type, min, max)
        def read_elements
          headers = {}
          each_csv("ELEHEAD.TXT") { |row| headers[row[0]] = row[1] }

          each_csv("ELEDETL.TXT") do |row|
            code = row[0]
            next if @elements_by_code.key?(code)

            x12_type = presence(row[1])
            min_length = positive_or_nil(row[2])
            max_length = positive_or_nil(row[3])

            digits = nil
            digits = Regexp.last_match(1).to_i if x12_type && x12_type =~ /^N(\d+)$/

            @elements_by_code[code] = Models::Element.new(
              code: code,
              name: headers[code] || "Element #{code}",
              description: nil,
              x12_type: x12_type,
              is_composite: false,
              min_length: min_length,
              max_length: max_length,
              digits: digits,
              element_codes: [],
              component_uses: []
            )
          end
        end

        # COMHEAD.TXT (code, name) - composites share the element pool.
        def read_composites
          each_csv("COMHEAD.TXT") do |row|
            code = row[0]
            next if @elements_by_code.key?(code)

            @elements_by_code[code] = Models::Element.new(
              code: code,
              name: row[1],
              description: nil,
              x12_type: nil,
              is_composite: true,
              min_length: nil,
              max_length: nil,
              digits: nil,
              element_codes: [],
              component_uses: []
            )
          end
        end

        # SEGHEAD.TXT (code, name)
        def read_segments
          each_csv("SEGHEAD.TXT") do |row|
            code = row[0]
            next if @segments_by_code.key?(code)

            @segments_by_code[code] = Models::Segment.new(
              code: code,
              name: row[1],
              purpose: nil,
              element_uses: [],
              syntax_notes: []
            )
          end
        end

        # SEGDETL.TXT (segment, position, element, requirement, repetition count)
        def read_element_uses
          each_csv("SEGDETL.TXT") do |row|
            segment = @segments_by_code[row[0]] or next
            element = @elements_by_code[row[2]] or next
            position = row[1].to_i

            next if segment.element_uses.any? { |eu| eu.position == position }

            segment.element_uses << Models::ElementUse.new(
              position: position,
              requirement: map_requirement(row[3]),
              element: element,
              max_reps: parse_element_reps(row[4])
            )
          end
        end

        # COMDETL.TXT (composite, position, element, requirement)
        def read_component_uses
          each_csv("COMDETL.TXT") do |row|
            composite = @elements_by_code[row[0]] or next
            element = @elements_by_code[row[2]] or next
            position = row[1].to_i

            next if composite.component_uses.any? { |cu| cu.position == position }

            composite.component_uses << Models::ComponentUse.new(
              position: position,
              requirement: map_requirement(row[3]),
              element: element
            )
          end
        end

        # SETHEAD.TXT (code, name, func_group) + SETDETL.TXT structure.
        def read_transaction_sets
          each_csv("SETHEAD.TXT") do |row|
            code = row[0]
            next if @transaction_sets_by_code.key?(code)

            @transaction_sets_by_code[code] = Models::TransactionSet.new(
              code: code,
              func_group: presence(row[2]),
              name: row[1],
              release: nil, # wired below
              table_definitions: []
            )
          end

          read_structure

          # Wire each transaction set back to its release and order its tables.
          @transaction_sets_by_code.each_value do |ts|
            ts.table_definitions.sort_by!(&:position)
          end
        end

        # SETDETL.TXT: ts, area, sequence, segment, requirement, max_use,
        # loop_level, loop_repeat, loop_id. Reconstructs the table/loop tree by
        # tracking a per-(ts, area) loop stack indexed by level.
        def read_structure
          tables_by_ts = Hash.new { |h, k| h[k] = {} }
          loop_stack_by_context = Hash.new { |h, k| h[k] = [] }

          each_csv("SETDETL.TXT") do |row|
            ts_code = row[0]
            area = row[1].to_i
            sequence = row[2]
            segment_code = row[3]
            requirement_code = row[4]
            max_use = row[5]
            loop_level = row[6].to_i
            loop_repeat = row[7]
            loop_id = presence(row[8])

            transaction_set = @transaction_sets_by_code[ts_code] or next
            segment = @segments_by_code[segment_code] or next

            table = (tables_by_ts[ts_code][area] ||= build_table(transaction_set, area))
            context_key = "#{ts_code}_#{area}"
            stack = loop_stack_by_context[context_key]

            parent =
              if loop_level.zero?
                loop_stack_by_context[context_key] = []
                table
              elsif loop_id
                # Every row carrying a loop_id opens a loop (member rows carry
                # an empty loop_id), and loop IDs are only unique within their
                # nesting context — the same ID can open distinct loops at
                # different positions in one area, so no caching by ID here.
                loop_parent = stack[loop_level - 1] || table

                loop_def = Models::LoopDefinition.new(
                  identifier: loop_id,
                  max_reps: parse_reps(loop_repeat),
                  position: sequence.to_i,
                  children: []
                )
                loop_parent.children << loop_def

                stack[loop_level] = loop_def
                loop_stack_by_context[context_key] = stack[0..loop_level]
                loop_def
              else
                stack[loop_level] || table
              end

            position = sequence.to_i
            next if parent.children.any? { |c| c.segment_use? && c.position == position }

            parent.children << Models::SegmentUse.new(
              segment: segment,
              x12_sequence: sequence,
              position: position,
              requirement: map_requirement(requirement_code),
              max_reps: parse_reps(max_use)
            )
          end
        end

        def build_table(transaction_set, area)
          name = { 1 => "Heading", 2 => "Detail", 3 => "Summary" }[area]
          enum = { 1 => "heading", 2 => "detail", 3 => "summary" }[area]

          table = Models::TableDefinition.new(area: enum, name: name, position: area, children: [])
          transaction_set.table_definitions << table
          table
        end

        # FREEFORM.TXT: tagged blocks. *ELECOD -> element code lists,
        # *SEGNTE (note type N) -> syntax notes. A block runs from one *TAG line
        # to the next; the final block is flushed at EOF (the Tediware importer
        # does not, dropping the last block - fixed here).
        def read_freeform
          path = find_file("FREEFORM.TXT")
          return unless path

          current_tag = nil
          current_data = []

          flush = lambda do
            process_freeform_block(current_tag, current_data) if current_tag && current_data.size >= 2
          end

          File.open(path, "r:#{ENCODING}") do |file|
            file.each_line do |line|
              line = line.encode("UTF-8", invalid: :replace, undef: :replace, replace: "").strip

              if line.start_with?("*")
                flush.call
                current_tag = line[1..]
                current_data = []
              elsif !line.empty?
                current_data << line
              end
            end
          end

          flush.call # EOF flush - emits the final block the importer drops
        end

        def process_freeform_block(tag, data)
          case tag
          when "ELECOD" then process_element_code(data)
          when "SEGNTE" then process_segment_note(data)
          end
        end

        def process_element_code(data)
          header = data[0].split(",").map(&:strip)
          element = @elements_by_code[header[0]] or return

          code_value = header[2]
          partition = presence(header[1])
          paragraph = [header[3].to_i, 1].max
          name = data[1..].join(" ")

          return if element.element_codes.any? { |ec| ec.code == code_value && ec.partition == partition }

          element.element_codes << Models::ElementCode.new(
            code: code_value,
            name: name,
            paragraph: paragraph,
            partition: partition
          )
        end

        SYNTAX_CONDITION = {
          "P" => "paired",
          "R" => "required",
          "C" => "conditional",
          "E" => "excluded",
          "L" => "list_conditional"
        }.freeze

        def process_segment_note(data)
          header = data[0].split(",").map(&:strip)
          segment = @segments_by_code[header[0]] or return
          note_type_code = header[2] # N = syntax, S = semantic, C = comment
          return unless note_type_code == "N"

          note_text = data[1..].join(" ")
          code = note_text.split.first
          return unless code && code.length >= 2

          condition_type = SYNTAX_CONDITION[code[0]] or return
          element_positions = code[1..].scan(/\d{2}/).map(&:to_i)

          if segment.syntax_notes.any? { |sn| sn.condition_type == condition_type && sn.element_positions == element_positions }
            return
          end

          segment.syntax_notes << Models::SyntaxNote.new(
            condition_type: condition_type,
            element_positions: element_positions,
            description: note_text
          )
        end

        # --- helpers -------------------------------------------------------

        def each_csv(filename)
          path = find_file(filename) or return
          CSV.foreach(path, encoding: ENCODING) { |row| yield row }
        end

        # Case-insensitive file lookup: X12 table data uses inconsistent casing
        # across releases (ELEHEAD.TXT vs elehead.txt). Returns nil if absent.
        def find_file(filename)
          exact = File.join(dir, filename)
          return exact if File.exist?(exact)

          Dir.glob(File.join(dir, "*")).find { |f| File.basename(f).casecmp?(filename) }
        end

        def map_requirement(code)
          case code
          when "M" then "Mandatory"
          when "O" then "Optional"
          when "C" then "Conditional"
          when "N" then "NotUsed"
          else "Optional"
          end
        end

        # ">1" means unbounded (nil); anything else is a fixed count.
        def parse_reps(value)
          value == ">1" ? nil : value.to_i
        end

        # SEGDETL field 5 is the element's repetition count. ">1" means unbounded
        # (nil); a blank, zero, or absent count is a single occurrence (1), which
        # the engine represents as RepeatCount.bounded(1) for a non-repeating use.
        def parse_element_reps(value)
          return nil if value == ">1"

          n = value.to_i
          n.positive? ? n : 1
        end

        def positive_or_nil(value)
          n = value.to_i
          n.positive? ? n : nil
        end

        def presence(value)
          return nil if value.nil?

          stripped = value.strip
          stripped.empty? ? nil : stripped
        end
      end
    end
  end
end
