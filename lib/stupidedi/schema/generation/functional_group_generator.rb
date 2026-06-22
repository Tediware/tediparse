# frozen_string_literal: true

module Stupidedi
  module Schema
    module Generation
      # Generates functional_group_def.rb - the GS/GE envelope for a release.
      class FunctionalGroupGenerator
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
          "#{namespace_path}/#{underscore(version_module)}/functional_group_def.rb"
        end

        private

        attr_reader :release

        def release_code
          release.code
        end

        def build_ruby_content
          <<~RUBY
            # frozen_string_literal: true
            require "tediparse"

            module #{namespace}
              module #{version_module}
                s = Stupidedi::Schema
                r = #{namespace}::#{version_module}::ElementReqs
                sd = #{namespace}::#{version_module}::SegmentDefs

                FunctionalGroupDef = Class.new(s::FunctionalGroupDef) do
                  # @return [FunctionalGroupVal]
                  def empty
                    Stupidedi::Values::FunctionalGroupVal.new(self, [])
                  end

                  # @return [Module]
                  def segment_dict
                    #{namespace}::#{version_module}::SegmentDefs
                  end
                end.new "#{release_code}",
                  [ sd::GS.use(1, r::Mandatory, s::RepeatCount.bounded(1)) ],
                  [ sd::GE.use(2, r::Mandatory, s::RepeatCount.bounded(1)) ]

              end
            end
          RUBY
        end
      end
    end
  end
end
