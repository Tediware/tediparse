# frozen_string_literal: true

require_relative "generation/version_modules"

module Stupidedi
  module Schema
    # Grammar generation: turns ASC X12 Table Data flat files into Stupidedi
    # grammar definition source files.
    #
    # The gem ships the generation *machine* only. The X12 Table Data it reads is
    # licensed X12 IP and is supplied by the consumer; the generated grammar
    # files are a derivative of that IP and belong to the consumer. Nothing here
    # bundles X12 content.
    #
    #   Stupidedi::Schema::Generation.run(
    #     table_data: "vendor/x12/table_data/005010",
    #     release:    "005010",
    #     out:        "lib"
    #   )
    module Generation
      autoload :Support,                  "stupidedi/schema/generation/support"
      autoload :Models,                   "stupidedi/schema/generation/models"
      autoload :FlatFileReader,           "stupidedi/schema/generation/flat_file_reader"
      autoload :SupportModulesGenerator,  "stupidedi/schema/generation/support_modules_generator"
      autoload :ElementGenerator,         "stupidedi/schema/generation/element_generator"
      autoload :SegmentGenerator,         "stupidedi/schema/generation/segment_generator"
      autoload :DefinitionGenerator,      "stupidedi/schema/generation/definition_generator"
      autoload :FunctionalGroupGenerator, "stupidedi/schema/generation/functional_group_generator"
      autoload :InterchangeGenerator,     "stupidedi/schema/generation/interchange_generator"
      autoload :ModuleLoaderGenerator,    "stupidedi/schema/generation/module_loader_generator"
      autoload :RegistrationGenerator,    "stupidedi/schema/generation/registration_generator"
      autoload :MasterLoaderGenerator,    "stupidedi/schema/generation/master_loader_generator"
      autoload :Runner,                   "stupidedi/schema/generation/runner"

      # Validates the output namespace is a single Ruby constant name and
      # returns it. Raises ArgumentError otherwise. See NAMESPACE_FORMAT.
      def self.validate_namespace!(namespace)
        return namespace if namespace.to_s =~ NAMESPACE_FORMAT

        raise ArgumentError,
          %(namespace must be a single Ruby constant name like "Edi" ) +
          %(got #{namespace.inspect}; nested namespaces ("::") are not supported)
      end

      # Generate the full grammar for one release. See Runner for options.
      # master_loader: true also emits a single-require entry file (e.g. edi.rb).
      def self.run(table_data:, release:, out:, namespace: "Edi", write: true, master_loader: false, logger: nil)
        Runner.new(
          table_data:    table_data,
          release:       release,
          out:           out,
          namespace:     namespace,
          write:         write,
          master_loader: master_loader,
          logger:        logger
        ).run
      end
    end
  end
end
