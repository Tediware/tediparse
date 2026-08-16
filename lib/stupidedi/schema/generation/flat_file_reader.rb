# frozen_string_literal: true

require "csv"

module Stupidedi
  module Schema
    module Generation
      # Reads ASC X12 Table Data flat files (the official .TXT distribution, CSV
      # despite the extension) and builds the in-memory Models tree the
      # generators consume. This is Layer A - the inverse of the Tediware
      # x12:import importer, with no database.
      #
      #   release = FlatFileReader.read("vendor/x12/table_data/005010", "005010")
      #
      # Files consumed: ELEHEAD/ELEDETL (simple elements), COMHEAD/COMDETL
      # (composites), SEGHEAD/SEGDETL (segments + element uses), SETHEAD/SETDETL
      # (transaction sets + structure), FREEFORM (code lists + syntax notes).
      #
      # The distribution's encoding varies by release - see SOURCE_ENCODINGS. It
      # is *not* ISO-8859-1 for any release we support, despite that being the
      # obvious guess: releases through 007010 are Windows-1252 and 008010 is
      # UTF-8.
      class FlatFileReader
        # Declared source encoding per ASC X12 release. CP1252 and ISO-8859-1
        # agree everywhere except 0x80-0x9F, which carries smart punctuation in
        # the former and undefined C1 controls in the latter - so reading a
        # CP1252 distribution as Latin-1 turns a curly apostrophe into U+0092
        # while leaving accented letters intact, which is why the damage hides.
        # 003060's and 004010's .TXT files are pure ASCII, so their entries are
        # a formality - declared anyway, because an undeclared release falls
        # through to the UTF-8 default and that is a decision, not an oversight.
        SOURCE_ENCODINGS = {
          "003060" => "Windows-1252",
          "004010" => "Windows-1252",
          "004060" => "Windows-1252",
          "005010" => "Windows-1252",
          "006010" => "Windows-1252",
          "007010" => "Windows-1252",
          "008010" => "UTF-8"
        }.freeze

        # An undeclared release decodes as UTF-8, deliberately. Single-byte
        # encodings decode every possible byte, so guessing one can only fail
        # silently; UTF-8 raises on the first byte that is not valid UTF-8, so a
        # new distribution nobody declared stops generation instead of writing
        # mojibake into the grammar.
        DEFAULT_SOURCE_ENCODING = "UTF-8"

        # CP1252 smart punctuation, normalized to ASCII after decoding. This is
        # not cosmetic: consumers derive identifiers and translated values from
        # these strings with ASCII-only munging (delete("'") and friends), so a
        # U+2019 survives the munging and stays damaged downstream. 008010's own
        # source already uses straight apostrophes, so this converges the older
        # releases onto what the newest one says. Punctuation only - accented
        # letters are left alone ("Fiancee", "Denominacion" and "Marzen" keep
        # their real characters).
        PUNCTUATION = {
          "‘" => "'",  # left single quotation mark
          "’" => "'",  # right single quotation mark
          "“" => '"',  # left double quotation mark
          "”" => '"',  # right double quotation mark
          "–" => "-",  # en dash
          "—" => "-"   # em dash
        }.freeze

        PUNCTUATION_PATTERN = Regexp.union(PUNCTUATION.keys).freeze

        # C1 controls are never legitimate in this data. Finding one after a
        # successful decode means the declared encoding is wrong (Latin-1 read
        # of CP1252 smart punctuation lands squarely here), so reject rather
        # than carry it into the generated grammar.
        C1_CONTROLS = (0x80..0x9F).map { |cp| cp.chr(Encoding::UTF_8) }.join.freeze

        # U+FEFF, spelled numerically because it is invisible in source.
        BOM = 0xFEFF.chr(Encoding::UTF_8).freeze

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
          path = find_file("SETDETL.TXT")

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

            where = structure_row(path, ts_code, area, sequence, segment_code)

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
                reject_zero_loop_id!(loop_id, where)
                loop_parent = stack[loop_level - 1] || table

                loop_def = Models::LoopDefinition.new(
                  identifier: loop_id,
                  max_reps: parse_reps!(loop_repeat, "loop repeat", where),
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
              max_reps: parse_reps!(max_use, "maximum use", where)
            )
          end
        end

        # Identifies one SETDETL row the way a human finds it in the file.
        def structure_row(path, ts_code, area, sequence, segment_code)
          "#{path}: transaction set #{ts_code}, area #{area}, sequence #{sequence} " \
            "(#{segment_code})"
        end

        # A zero repeat count is not representable: RepeatCount.bounded(0)
        # raises, so the emitted grammar dies the moment a consumer loads it,
        # naming neither the release nor the transaction set nor the row - by
        # then the source distribution is a long way behind you. Catch it here,
        # where the row can still be pointed at.
        #
        # Both this and reject_zero_loop_id! guard the same underlying defect: a
        # column shift in the source distribution, where a value lands one field
        # left of where it belongs and the neighbouring release carries the row
        # correctly.
        def parse_reps!(value, column, where)
          reps = parse_reps(value)
          return reps if reps.nil? || reps.positive?

          raise ArgumentError,
            "#{where}: #{column} #{value.inspect} parses to a repeat count of #{reps}, which no loop " \
            "or segment can carry. The row is defective, usually a column shift - compare it " \
            "against the same row in a neighbouring release and correct it in the table data."
        end

        # The shift is worse when it lands in the loop id column, because
        # nothing downstream objects: a loop identified as "0" builds, loads and
        # parses, quietly reparenting every row that follows it.
        def reject_zero_loop_id!(loop_id, where)
          return unless loop_id == "0"

          raise ArgumentError,
            "#{where}: \"0\" is not a loop identifier. The row is defective, usually a column " \
            "shift - compare it against the same row in a neighbouring release and correct it " \
            "in the table data."
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

          read_source(path).each_line do |line|
            line = line.strip

            if line.start_with?("*")
              flush.call
              current_tag = line[1..]
              current_data = []
            elsif !line.empty?
              current_data << line
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
          CSV.parse(read_source(path)) { |row| yield row }
        end

        # Reads one table-data file and returns validated, normalized UTF-8.
        #
        # The whole file is decoded up front rather than streamed: these files
        # are small, and one decode point is what makes the encoding a single
        # declared fact instead of something each read site guesses at.
        def read_source(path)
          text = decode(path)
          text = text.gsub(PUNCTUATION_PATTERN, PUNCTUATION)
          reject_c1_controls!(text, path)
          text
        end

        def decode(path)
          raw = File.binread(path).force_encoding(source_encoding)
          raise decode_error(path, "invalid byte sequence") unless raw.valid_encoding?

          # A UTF-8 BOM would otherwise ride along in the first field of the
          # first record and corrupt its key.
          raw.encode("UTF-8").delete_prefix(BOM)
        rescue Encoding::UndefinedConversionError, Encoding::InvalidByteSequenceError => e
          raise decode_error(path, e.message)
        end

        def source_encoding
          SOURCE_ENCODINGS.fetch(release_code, DEFAULT_SOURCE_ENCODING)
        end

        def decode_error(path, detail)
          provenance =
            if SOURCE_ENCODINGS.key?(release_code)
              "declared for release #{release_code}: #{detail}. Correct that release's entry in"
            else
              "assumed for release #{release_code}, which is not declared: #{detail}. " \
                "Add the release's real encoding to"
            end

          ArgumentError.new(
            "Could not decode #{path} as #{source_encoding}, #{provenance} " \
            "#{self.class}::SOURCE_ENCODINGS."
          )
        end

        def reject_c1_controls!(text, path)
          return if text.count(C1_CONTROLS).zero?

          text.each_line.with_index(1) do |line, lineno|
            char = line.each_char.find { |c| C1_CONTROLS.include?(c) } or next

            raise ArgumentError,
              format("C1 control character U+%04X at %s line %d, which means release %s is not " \
                     "%s. Correct %s::SOURCE_ENCODINGS.",
                     char.ord, path, lineno, release_code, source_encoding, self.class)
          end
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
