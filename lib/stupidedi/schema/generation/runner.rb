# frozen_string_literal: true

require "fileutils"
require "tmpdir"

module Stupidedi
  module Schema
    module Generation
      # Orchestrates a full-release generation run. Reads the flat files, then
      # runs every generator in dependency order. Mirrors the Tediware
      # +stupidedi:generate_version+ pipeline.
      #
      # All files are generated into a temporary staging directory first. The
      # registration and master-loader generators scan that staging tree (not
      # the live +out+), so their content is always consistent with the run -
      # including under write: false (dry-run previews are accurate). On a
      # successful write run the staging tree is copied into +out+ in one step,
      # so a failure partway through never leaves a half-written tree.
      class Runner
        # Describes one generated file.
        Result = Struct.new(:path, :relative_path, :content, :written, keyword_init: true)

        def initialize(table_data:, release:, out:, namespace: "Edi", write: true, master_loader: false, logger: nil)
          @table_data = table_data
          @release_code = release
          @out = out
          @namespace = namespace
          @write = write
          @master_loader = master_loader
          @logger = logger
        end

        # @return [Array<Result>] one entry per generated file
        def run
          Generation.validate_namespace!(@namespace)
          validate_release!

          release = FlatFileReader.read(@table_data, @release_code)
          guard_against_empty!(release)
          log "Read release #{release.code}: " \
              "#{release.elements.size} elements, #{release.segments.size} segments, " \
              "#{release.transaction_sets.size} transaction sets"

          results = []
          Dir.mktmpdir("tediparse-gen") do |staging|
            @staging = staging
            results = generate_all(release)
            if @write
              ensure_out
              replace_staged_release_dirs
              FileUtils.cp_r(File.join(staging, "."), @out)
            end
          end

          log "#{@write ? 'Wrote' : 'Previewed'} #{results.size} files under #{@out}"
          results
        end

        private

        def generate_all(release)
          results = []
          results.concat(run_support_modules(release))
          results << emit(ElementGenerator.new(release, namespace: @namespace))
          results << emit(SegmentGenerator.new(release, include_control_segments: true, namespace: @namespace))
          results << emit(FunctionalGroupGenerator.new(release, namespace: @namespace))
          results << emit(ModuleLoaderGenerator.new(release, namespace: @namespace))
          results << emit(InterchangeGenerator.new(release, namespace: @namespace))

          release.transaction_sets.each do |ts|
            results << emit(DefinitionGenerator.new(ts, namespace: @namespace))
          end

          # Registration and master loader are whole-tree artifacts. They scan
          # [staging, out] so the emitted files cover the release just generated
          # (in staging) UNION the releases already present under out, with
          # staging shadowing out for the regenerated release. This keeps a
          # multi-release output tree consistent and makes dry-run previews
          # reflect the true resulting tree.
          roots = [@staging, @out]
          results << emit(RegistrationGenerator.new(roots: roots, namespace: @namespace))
          results << emit(MasterLoaderGenerator.new(roots: roots, namespace: @namespace)) if @master_loader
          results
        end

        def run_support_modules(release)
          generator = SupportModulesGenerator.new(release, namespace: @namespace)
          paths = generator.output_paths
          generator.generate_all.map do |mod, content|
            write_result(paths[mod], content)
          end
        end

        def emit(generator)
          write_result(generator.output_path, generator.generate)
        end

        # Always writes into the staging tree (so the disk-scanning generators
        # see a complete, consistent picture); the staging tree is copied to
        # +out+ once, at the end, only on a successful write run.
        def write_result(relative_path, content)
          staged_path = File.join(@staging, relative_path)
          FileUtils.mkdir_p(File.dirname(staged_path))
          File.write(staged_path, content)

          full_path = File.join(@out, relative_path)
          log(@write ? "  #{full_path}" : "  would write #{full_path} (#{content.lines.size} lines)")

          Result.new(path: full_path, relative_path: relative_path, content: content, written: @write)
        end

        def validate_release!
          return if VERSION_MODULES.key?(@release_code)

          raise ArgumentError, "Unsupported release code: #{@release_code}. " \
            "Supported: #{VERSION_MODULES.keys.join(', ')}"
        end

        def guard_against_empty!(release)
          return unless release.segments.empty? || release.elements.empty?

          raise ArgumentError,
            "No X12 table data found in #{@table_data} " \
            "(expected ELEDETL.TXT, SEGHEAD.TXT, SETHEAD.TXT, ... — got " \
            "#{release.elements.size} elements, #{release.segments.size} segments). " \
            "Check the --table-data path points at the release's table-data directory."
        end

        def ensure_out
          FileUtils.mkdir_p(@out)
          @out
        end

        # Remove the live-tree counterpart of every release directory the staging
        # tree is about to deliver, so the regenerated release REPLACES (rather
        # than merges into) what was there. Without this, a regeneration whose
        # transaction-set list shrank would leave orphaned standards/*.rb behind -
        # which the run itself shadows correctly, but which would later mislead a
        # standalone Generation.register scan. The shared `interchanges/` dir and
        # other releases are left untouched.
        def replace_staged_release_dirs
          Dir.glob(File.join(@staging, "*")).each do |namespace_dir|
            next unless File.directory?(namespace_dir)

            namespace_name = File.basename(namespace_dir)
            Dir.glob(File.join(namespace_dir, "*")).each do |release_dir|
              next unless File.directory?(release_dir)
              next if File.basename(release_dir) == "interchanges"

              FileUtils.rm_rf(File.join(@out, namespace_name, File.basename(release_dir)))
            end
          end
        end

        def log(message)
          @logger&.call(message)
        end
      end
    end
  end
end
