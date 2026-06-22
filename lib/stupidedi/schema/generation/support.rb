# frozen_string_literal: true

module Stupidedi
  module Schema
    module Generation
      # Shared helpers mixed into every generator.
      #
      # The host class must provide a private +#release_code+ returning the
      # 6-character release string (e.g. "005010") and may set +@namespace+,
      # the root Ruby module for the emitted code (defaults to "Edi").
      module Support
        # Root module for generated constants, e.g. "Edi". Consumers override
        # this to emit into their own namespace. Validated (and memoized) on
        # first use so an invalid namespace fails before any code is emitted.
        def namespace
          @validated_namespace ||= Generation.validate_namespace!(@namespace || "Edi")
        end

        # Filesystem/require-path root derived from the namespace ("Edi" -> "edi").
        def namespace_path
          underscore(namespace)
        end

        private

        def version_module
          VERSION_MODULES.fetch(release_code)
        end

        def validate_release!
          return if VERSION_MODULES.key?(release_code)

          raise ArgumentError, "Unsupported release code: #{release_code}. " \
            "Supported: #{VERSION_MODULES.keys.join(', ')}"
        end

        def format_requirement(requirement)
          stupidedi_req = REQUIREMENT_MAP.fetch(requirement) do
            raise ArgumentError, "Unknown requirement: #{requirement}"
          end
          "r::#{stupidedi_req}"
        end

        def escape_string(str)
          return '""' if str.nil? || str.empty?

          escaped = str.gsub('\\', '\\\\\\\\').gsub('"', '\\"')
          "\"#{escaped}\""
        end

        def indent(level)
          "  " * level
        end

        # Convert release code to interchange version code.
        # "004010" -> "00401", "005010" -> "00501"
        def interchange_version_code
          release_code[0..4]
        end

        # Minimal ActiveSupport-free String#underscore.
        # "FortyTen" -> "forty_ten", "FourOhOne" -> "four_oh_one"
        def underscore(str)
          str.gsub("::", "/")
             .gsub(/([A-Z]+)([A-Z][a-z])/, '\1_\2')
             .gsub(/([a-z\d])([A-Z])/, '\1_\2')
             .downcase
        end

        # Minimal ActiveSupport-free String#camelize.
        # "forty_ten" -> "FortyTen", "four_oh_one" -> "FourOhOne"
        def camelize(str)
          str.split(%r{[_/]}).reject(&:empty?).map { |part| part[0].upcase + part[1..] }.join
        end
      end
    end
  end
end
