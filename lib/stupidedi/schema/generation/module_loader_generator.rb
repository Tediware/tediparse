# frozen_string_literal: true

module Stupidedi
  module Schema
    module Generation
      # Generates the top-level per-version module file (e.g. forty_ten.rb).
      #
      # It declares the module and nothing else. An explicit relative-path
      # autoload here would replace the absolute one Zeitwerk registers, and
      # Zeitwerk would then attribute the require to whatever file is last in
      # $LOADED_FEATURES, which a concurrent autoload on another thread can
      # change. Consumers without an autoloader get the support files from the
      # master loader instead (see MasterLoaderGenerator::SUPPORT_FILES).
      class ModuleLoaderGenerator
        include Support

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
          <<~RUBY
            # frozen_string_literal: true
            module #{namespace}
              module #{version_module}
              end
            end
          RUBY
        end
      end
    end
  end
end
