# frozen_string_literal: true

module Stupidedi
  module Schema
    module Generation
      # Generates the four small per-version wrapper modules that alias common
      # Stupidedi types into the version-scoped namespace so the other generated
      # files can use short names.
      class SupportModulesGenerator
        include Support

        SUPPORT_MODULES = %i[element_reqs element_types segment_reqs syntax_notes].freeze

        def initialize(release, namespace: "Edi")
          @release = release
          @namespace = namespace
        end

        def generate_all
          validate_release!
          SUPPORT_MODULES.to_h { |mod| [mod, send(:"generate_#{mod}")] }
        end

        def output_paths
          base_path = "#{namespace_path}/#{underscore(version_module)}"
          SUPPORT_MODULES.to_h { |mod| [mod, "#{base_path}/#{mod}.rb"] }
        end

        def generate_element_reqs
          <<~RUBY
            # frozen_string_literal: true

            require "tediparse"

            module #{namespace}
              module #{version_module}
                module ElementReqs
                  Mandatory  = Stupidedi::Versions::Common::ElementReqs::Mandatory
                  Optional   = Stupidedi::Versions::Common::ElementReqs::Optional
                  Relational = Stupidedi::Versions::Common::ElementReqs::Relational
                end
              end
            end
          RUBY
        end

        def generate_element_types
          <<~RUBY
            # frozen_string_literal: true

            require "tediparse"

            module #{namespace}
              module #{version_module}
                module ElementTypes
                  DT               = Stupidedi::Versions::Common::ElementTypes::DT
                  DateVal          = Stupidedi::Versions::Common::ElementTypes::DateVal

                  R                = Stupidedi::Versions::Common::ElementTypes::R
                  FloatVal         = Stupidedi::Versions::Common::ElementTypes::FloatVal

                  ID               = Stupidedi::Versions::Common::ElementTypes::ID
                  IdentifierVal    = Stupidedi::Versions::Common::ElementTypes::IdentifierVal

                  Nn               = Stupidedi::Versions::Common::ElementTypes::Nn
                  FixnumVal        = Stupidedi::Versions::Common::ElementTypes::FixnumVal

                  AN               = Stupidedi::Versions::Common::ElementTypes::AN
                  StringVal        = Stupidedi::Versions::Common::ElementTypes::StringVal

                  TM               = Stupidedi::Versions::Common::ElementTypes::TM
                  TimeVal          = Stupidedi::Versions::Common::ElementTypes::TimeVal

                  SimpleElementDef = Stupidedi::Versions::Common::ElementTypes::SimpleElementDef
                end
              end
            end
          RUBY
        end

        def generate_segment_reqs
          <<~RUBY
            # frozen_string_literal: true

            require "tediparse"

            module #{namespace}
              module #{version_module}
                module SegmentReqs
                  Mandatory = Stupidedi::Versions::Common::SegmentReqs::Mandatory
                  Optional  = Stupidedi::Versions::Common::SegmentReqs::Optional
                end
              end
            end
          RUBY
        end

        def generate_syntax_notes
          <<~RUBY
            # frozen_string_literal: true

            module #{namespace}
              module #{version_module}
                module SyntaxNotes
                  P = Stupidedi::Versions::Common::SyntaxNotes::P
                  R = Stupidedi::Versions::Common::SyntaxNotes::R
                  E = Stupidedi::Versions::Common::SyntaxNotes::E
                  C = Stupidedi::Versions::Common::SyntaxNotes::C
                  L = Stupidedi::Versions::Common::SyntaxNotes::L
                end
              end
            end
          RUBY
        end

        private

        attr_reader :release

        def release_code
          release.code
        end
      end
    end
  end
end
