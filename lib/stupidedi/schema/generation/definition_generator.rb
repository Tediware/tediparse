# frozen_string_literal: true

module Stupidedi
  module Schema
    module Generation
      # Generates one transaction-set standard file (e.g. SM204.rb). Walks the
      # transaction set's table definitions and recursively emits loops and
      # segment uses. This is the heart of the grammar.
      class DefinitionGenerator
        include Support

        AREA_METHODS = {
          "heading" => "header",
          "detail"  => "detail",
          "summary" => "summary"
        }.freeze

        def initialize(transaction_set, namespace: "Edi")
          @transaction_set = transaction_set
          @namespace = namespace
        end

        def generate
          validate_release!
          build_ruby_content
        end

        def constant_name
          func_group = transaction_set.func_group
          code = transaction_set.code
          # If func_group is nil/empty, prefix with 'TS' to create a valid Ruby constant
          func_group = "TS" if func_group.nil? || func_group.empty?
          "#{func_group}#{code}"
        end

        def output_path
          "#{namespace_path}/#{underscore(version_module)}/standards/#{constant_name}.rb"
        end

        private

        attr_reader :transaction_set

        def release_code
          transaction_set.release.code
        end

        def build_ruby_content
          lines = []
          lines << 'require "tediparse"'
          lines << "if !defined?(#{namespace}::#{version_module}::Standards::#{constant_name})"
          lines << "  module #{namespace}"
          lines << "    module #{version_module}"
          lines << "      module Standards"
          lines << "        b = Stupidedi::TransactionSets::Builder"
          lines << "        d = Stupidedi::Schema"
          lines << "        r = #{namespace}::#{version_module}::SegmentReqs"
          lines << "        s = #{namespace}::#{version_module}::SegmentDefs"
          lines << build_transaction_set_definition
          lines << "      end"
          lines << "    end"
          lines << "  end"
          lines << "end"
          lines.join("\n") + "\n"
        end

        def build_transaction_set_definition
          tables = transaction_set.table_definitions.to_a
          table_defs = tables.each_with_index.map do |table, index|
            generate_table_def(table, is_last: index == tables.length - 1)
          end

          header = %[        #{constant_name} = b.build("#{transaction_set.func_group}", "#{transaction_set.code}", "#{transaction_set.name}",]
          footer = "        )"

          [header, *table_defs, footer].join("\n")
        end

        def generate_table_def(table, is_last:)
          area_method = AREA_METHODS.fetch(table.area)
          children = table.ordered_children

          child_lines = children.each_with_index.map do |child, index|
            child_is_last = index == children.length - 1
            generate_child(child, indent_level: 6, is_last: child_is_last)
          end

          trailing_comma = is_last ? "" : ","
          header = %[#{indent(5)}d::TableDef.#{area_method}("#{table.name}",]
          footer = "#{indent(5)})#{trailing_comma}"

          [header, *child_lines, footer].join("\n")
        end

        def generate_child(child, indent_level:, is_last:)
          if child.segment_use?
            generate_segment_use(child, indent_level: indent_level, is_last: is_last)
          else
            generate_loop_def(child, indent_level: indent_level, is_last: is_last)
          end
        end

        def generate_loop_def(loop, indent_level:, is_last:)
          children = loop.ordered_children
          repeat_count = format_repeat_count(loop.max_reps)

          child_lines = children.each_with_index.map do |child, index|
            child_is_last = index == children.length - 1
            generate_child(child, indent_level: indent_level + 1, is_last: child_is_last)
          end

          trailing_comma = is_last ? "" : ","
          header = %[#{indent(indent_level)}d::LoopDef.build("#{loop.identifier}", #{repeat_count},]
          footer = "#{indent(indent_level)})#{trailing_comma}"

          [header, *child_lines, footer].join("\n")
        end

        def generate_segment_use(segment_use, indent_level:, is_last:)
          segment_code = segment_use.segment.code
          position = (segment_use.x12_sequence || segment_use.position).to_i
          requirement = format_requirement(segment_use.requirement)
          repeat_count = format_repeat_count(segment_use.max_reps)

          trailing_comma = is_last ? "" : ","
          "#{indent(indent_level)}s::#{segment_code}.use(#{position}, #{requirement}, #{repeat_count})#{trailing_comma}"
        end

        def format_repeat_count(max_reps)
          if max_reps.nil?
            "d::RepeatCount.unbounded"
          else
            "d::RepeatCount.bounded(#{max_reps})"
          end
        end
      end
    end
  end
end
