# frozen_string_literal: true

module Stupidedi
  module Schema
    module Generation
      # Generates stupidedi_registration.rb. Does not read X12 data - instead it
      # scans the already-generated files under the output directory and emits a
      # register(config) method plus INTERCHANGE_VERSIONS / FUNCTIONAL_GROUP_VERSIONS
      # constants. Always run last so it picks up freshly generated files.
      class RegistrationGenerator
        include Support

        WORDS_TO_DIGITS = {
          "Oh" => "0",  "One" => "1", "Two" => "2",   "Three" => "3", "Four" => "4",
          "Five" => "5", "Six" => "6", "Seven" => "7", "Eight" => "8", "Nine" => "9"
        }.freeze

        # @param out [String] base directory the grammar tree was written under
        #   (the same +out+ passed to the other generators)
        def initialize(out:, namespace: "Edi")
          @out = out
          @namespace = namespace
          @registrations = {
            interchanges: {},
            functional_groups: {},
            transaction_sets: {}
          }
        end

        def generate
          scan_existing_definitions
          build_ruby_content
        end

        def output_path
          "#{namespace_path}/stupidedi_registration.rb"
        end

        private

        attr_reader :registrations, :out

        def root
          File.join(out, namespace_path)
        end

        def scan_existing_definitions
          scan_transaction_sets
          scan_functional_groups
          scan_interchanges
        end

        def scan_transaction_sets
          escaped = Regexp.escape(namespace_path)
          pattern = %r{#{escaped}/([^/]+)/standards/([A-Z]{2})(\d{3})\.rb$}

          Dir.glob(File.join(root, "*", "standards", "*.rb")).each do |path|
            match = path.match(pattern)
            next unless match

            version_dir = match[1]
            func_group = match[2]
            ts_code = match[3]

            version_module = directory_to_module(version_dir)
            next unless VERSION_MODULES.value?(version_module)

            release_code = module_to_release_code(version_module)
            # Handle constants like TS980 (when func_group is nil/empty in source)
            const_prefix = func_group.length == 2 ? func_group : "TS"
            constant_name = "#{namespace}::#{version_module}::Standards::#{const_prefix}#{ts_code}"

            # Extract func_group for registration - TS means nil/empty func_group
            reg_func_group = const_prefix == "TS" ? nil : func_group

            registrations[:transaction_sets][release_code] ||= []
            registrations[:transaction_sets][release_code] << {
              func_group: reg_func_group,
              ts_code: ts_code,
              constant: constant_name
            }
          end

          # Sort transaction sets within each release (handle nil func_group)
          registrations[:transaction_sets].each_value do |ts_list|
            ts_list.sort_by! { |ts| [ts[:func_group] || "ZZ", ts[:ts_code]] }
          end
        end

        def scan_functional_groups
          escaped = Regexp.escape(namespace_path)
          pattern = %r{#{escaped}/([^/]+)/functional_group_def\.rb$}

          Dir.glob(File.join(root, "*", "functional_group_def.rb")).each do |path|
            match = path.match(pattern)
            next unless match

            version_dir = match[1]
            version_module = directory_to_module(version_dir)
            next unless VERSION_MODULES.value?(version_module)

            release_code = module_to_release_code(version_module)
            constant_name = "#{namespace}::#{version_module}::FunctionalGroupDef"

            registrations[:functional_groups][release_code] = constant_name
          end
        end

        def scan_interchanges
          Dir.glob(File.join(root, "interchanges", "*.rb")).each do |path|
            match = path.match(%r{interchanges/([^/]+)\.rb$})
            next unless match

            file_name = match[1]
            module_name = file_to_interchange_module(file_name)
            interchange_code = interchange_module_to_code(module_name)

            constant_name = "#{namespace}::Interchanges::#{module_name}::InterchangeDef"

            registrations[:interchanges][interchange_code] = constant_name
          end
        end

        def directory_to_module(dir_name)
          # forty_ten -> FortyTen, forty_sixty -> FortySixty, fifty_ten -> FiftyTen
          camelize(dir_name)
        end

        def module_to_release_code(version_module)
          VERSION_MODULES.key(version_module)
        end

        # Convert "four_oh_one" -> "FourOhOne"
        def file_to_interchange_module(file_name)
          camelize(file_name)
        end

        # Convert "FourOhOne" -> "00401", "FiveOhOne" -> "00501"
        def interchange_module_to_code(module_name)
          result = module_name.dup
          WORDS_TO_DIGITS.each do |word, digit|
            result = result.gsub(word, digit)
          end
          # Pad to 5 digits with leading zeros (interchange codes are 5 chars)
          result.rjust(5, "0")
        end

        def build_ruby_content
          lines = []
          lines << "# frozen_string_literal: true"
          lines << ""
          lines << "# Auto-generated by Stupidedi::Schema::Generation::RegistrationGenerator"
          lines << "# DO NOT EDIT MANUALLY"
          lines << ""
          lines << "module #{namespace}"
          lines << "  module StupidediRegistration"
          lines << build_version_constants
          lines << ""
          lines << "    def self.register(config)"
          lines << "      register_interchanges(config)"
          lines << "      register_functional_groups(config)"
          lines << "      register_transaction_sets(config)"
          lines << "    end"
          lines << ""
          lines << build_interchange_registration
          lines << ""
          lines << build_functional_group_registration
          lines << ""
          lines << build_transaction_set_registration
          lines << "  end"
          lines << "end"
          lines.join("\n") + "\n"
        end

        def build_version_constants
          interchange_codes = registrations[:interchanges].keys.sort
          functional_group_codes = registrations[:functional_groups].keys.sort

          lines = []
          lines << "    INTERCHANGE_VERSIONS = %w[#{interchange_codes.join(' ')}].freeze"
          lines << "    FUNCTIONAL_GROUP_VERSIONS = %w[#{functional_group_codes.join(' ')}].freeze"
          lines.join("\n")
        end

        def build_interchange_registration
          lines = []
          lines << "    def self.register_interchanges(config)"
          lines << "      config.interchange.customize do |x|"

          registrations[:interchanges].keys.sort.each do |code|
            constant = registrations[:interchanges][code]
            lines << "        x.register(\"#{code}\") { #{constant} }"
          end

          lines << "      end"
          lines << "    end"
          lines.join("\n")
        end

        def build_functional_group_registration
          lines = []
          lines << "    def self.register_functional_groups(config)"
          lines << "      config.functional_group.customize do |x|"

          registrations[:functional_groups].keys.sort.each do |code|
            constant = registrations[:functional_groups][code]
            lines << "        x.register(\"#{code}\") { #{constant} }"
          end

          lines << "      end"
          lines << "    end"
          lines.join("\n")
        end

        def build_transaction_set_registration
          lines = []
          lines << "    def self.register_transaction_sets(config)"
          lines << "      config.transaction_set.customize do |x|"

          registrations[:transaction_sets].keys.sort.each do |release_code|
            ts_list = registrations[:transaction_sets][release_code]
            ts_list.each do |ts|
              # Skip transaction sets without a functional group - they can't be registered
              next if ts[:func_group].nil?

              lines << "        x.register(\"#{release_code}\", \"#{ts[:func_group]}\", \"#{ts[:ts_code]}\") { #{ts[:constant]} }"
            end
          end

          lines << "      end"
          lines << "    end"
          lines.join("\n")
        end
      end
    end
  end
end
