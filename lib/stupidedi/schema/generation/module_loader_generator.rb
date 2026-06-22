# frozen_string_literal: true

module Stupidedi
  module Schema
    module Generation
      # Generates the top-level per-version loader file (e.g. forty_ten.rb) with
      # autoload statements in dependency order.
      class ModuleLoaderGenerator
        include Support

        # Autoload order matters - dependencies must be loaded first
        AUTOLOAD_MODULES = %w[
          ElementReqs
          ElementTypes
          SegmentReqs
          SyntaxNotes
          ElementDefs
          SegmentDefs
          FunctionalGroupDef
        ].freeze

        def initialize(release, namespace: "Edi")
          @release = release
          @namespace = namespace
        end

        def generate
          validate_release!
          build_ruby_content
        end

        def output_path
          "#{namespace_path}/#{underscore(version_module)}.rb"
        end

        private

        attr_reader :release

        def release_code
          release.code
        end

        def build_ruby_content
          base_path = "#{namespace_path}/#{underscore(version_module)}"
          autoloads = AUTOLOAD_MODULES.map do |mod|
            file_name = underscore(mod)
            padding = " " * (18 - mod.length)
            "    autoload :#{mod},#{padding}\"#{base_path}/#{file_name}\""
          end

          <<~RUBY
            # frozen_string_literal: true
            module #{namespace}
              module #{version_module}
            #{autoloads.join("\n")}
              end
            end
          RUBY
        end
      end
    end
  end
end
