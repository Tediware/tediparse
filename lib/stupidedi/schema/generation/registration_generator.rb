# frozen_string_literal: true

module Stupidedi
  module Schema
    module Generation
      # Generates stupidedi_registration.rb. Does not read X12 data - instead it
      # scans already-generated files and emits a register(config) method plus
      # INTERCHANGE_VERSIONS / FUNCTIONAL_GROUP_VERSIONS constants.
      #
      # The registration is a *whole-tree* artifact: it must list every release
      # present in the output tree, not just one. It therefore scans an ordered
      # list of roots and unions the releases it finds. Earlier roots shadow
      # later ones per release, so a run can scan [staging, out] and aggregate
      # the freshly generated release (in staging) with the releases already
      # committed under out, without listing either twice.
      class RegistrationGenerator
        include Support

        WORDS_TO_DIGITS = {
          "Oh" => "0",  "One" => "1", "Two" => "2",   "Three" => "3", "Four" => "4",
          "Five" => "5", "Six" => "6", "Seven" => "7", "Eight" => "8", "Nine" => "9"
        }.freeze

        # @param roots [String, Array<String>] one or more base directories (each
        #   containing <namespace_path>/...). Earlier roots win per release.
        def initialize(roots:, namespace: "Edi")
          @roots = Array(roots)
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

        attr_reader :registrations, :roots

        def namespace_roots
          roots.map { |r| File.join(r, namespace_path) }
        end

        # Yields each release's version directory once, with earlier roots
        # shadowing later ones for the same release.
        def each_version_dir
          seen = {}
          namespace_roots.each do |base|
            Dir.glob(File.join(base, "*")).each do |dir|
              next unless File.directory?(dir)

              dir_name = File.basename(dir)
              version_module = camelize(dir_name)
              next unless VERSION_MODULES.value?(version_module)
              next if seen[dir_name]

              seen[dir_name] = true
              yield dir, version_module, module_to_release_code(version_module)
            end
          end
        end

        def scan_existing_definitions
          scan_transaction_sets
          scan_functional_groups
          scan_interchanges
        end

        def scan_transaction_sets
          each_version_dir do |version_dir, version_module, release_code|
            Dir.glob(File.join(version_dir, "standards", "*.rb")).each do |path|
              match = File.basename(path).match(/\A([A-Z]{2})(\d{3})\.rb\z/)
              next unless match

              func_group = match[1]
              ts_code = match[2]
              # A "TS" prefix encodes a nil/empty functional group (see
              # DefinitionGenerator#constant_name).
              constant_name = "#{namespace}::#{version_module}::Standards::#{func_group}#{ts_code}"
              reg_func_group = func_group == "TS" ? nil : func_group

              (registrations[:transaction_sets][release_code] ||= []) << {
                func_group: reg_func_group,
                ts_code: ts_code,
                constant: constant_name
              }
            end
          end

          # Sort transaction sets within each release (handle nil func_group)
          registrations[:transaction_sets].each_value do |ts_list|
            ts_list.sort_by! { |ts| [ts[:func_group] || "ZZ", ts[:ts_code]] }
          end
        end

        def scan_functional_groups
          each_version_dir do |version_dir, version_module, release_code|
            next unless File.exist?(File.join(version_dir, "functional_group_def.rb"))

            registrations[:functional_groups][release_code] =
              "#{namespace}::#{version_module}::FunctionalGroupDef"
          end
        end

        def scan_interchanges
          namespace_roots.each do |base|
            Dir.glob(File.join(base, "interchanges", "*.rb")).each do |path|
              module_name = camelize(File.basename(path, ".rb"))
              interchange_code = interchange_module_to_code(module_name)

              # ||= so an earlier root (e.g. staging) wins on collision.
              registrations[:interchanges][interchange_code] ||=
                "#{namespace}::Interchanges::#{module_name}::InterchangeDef"
            end
          end
        end

        def module_to_release_code(version_module)
          VERSION_MODULES.key(version_module)
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
