# frozen_string_literal: true

module Stupidedi
  module Schema
    module Generation
      # Generates an interchange (ISA/IEA envelope) file. Detects the component
      # separator from ISA element positions and whether the release supports a
      # repetition separator (I65 in ISA11), and emits replace_separators.
      class InterchangeGenerator
        include Support

        WORDS = {
          "0" => "Oh",  "1" => "One", "2" => "Two",   "3" => "Three", "4" => "Four",
          "5" => "Five", "6" => "Six", "7" => "Seven", "8" => "Eight", "9" => "Nine"
        }.freeze

        def initialize(release, namespace: "Edi")
          @release = release
          @namespace = namespace
        end

        def generate
          validate_release!
          build_ruby_content
        end

        def output_path
          "#{namespace_path}/interchanges/#{interchange_file_name}.rb"
        end

        private

        attr_reader :release

        def release_code
          release.code
        end

        # Convert "00401" -> "FourOhOne", "00406" -> "FourOhSix", "00501" -> "FiveOhOne"
        # Ignore leading zeros, then convert remaining digits to words.
        def interchange_module_name
          significant = interchange_version_code.sub(/^0+/, "")
          significant.chars.map { |d| WORDS[d] }.join
        end

        # Convert "FourOhOne" -> "four_oh_one"
        def interchange_file_name
          underscore(interchange_module_name)
        end

        def isa_segment
          @isa_segment ||= release.segments.find { |s| s.code == "ISA" } ||
            raise(ArgumentError, "Release #{release_code} has no ISA segment")
        end

        def has_repetition_separator?
          position_11_use = isa_segment.element_uses.find { |eu| eu.position == 11 }
          return false unless position_11_use

          position_11_use.element.code == "I65"
        end

        def separators_method
          if has_repetition_separator?
            "Stupidedi::Reader::Separators.new(isa.element(16).to_s, isa.element(11).to_s, nil, nil)"
          else
            "Stupidedi::Reader::Separators.new(isa.element(16).to_s, nil, nil, nil)"
          end
        end

        def replace_separators_method
          isa_element_count = isa_segment.element_uses.size

          element_refs = (1...isa_element_count).map do |i|
            "               isa.element(#{i}),"
          end
          # Last element gets the separators.component replacement
          element_refs << "               isa.element(#{isa_element_count}).copy(:value => separators.component)]"

          <<~RUBY.strip
            # @return [SegmentVal]
                    def replace_separators(isa, separators)
                      isa.copy \\
                        :separators => separators,
                        :children   =>
                          [#{element_refs.first.strip}
            #{element_refs[1..].join("\n")}
                    end
          RUBY
        end

        def build_ruby_content
          <<~RUBY
            # frozen_string_literal: true
            require "tediparse"

            module #{namespace}
              module Interchanges
                module #{interchange_module_name}
                  s = Stupidedi::Schema
                  r = #{namespace}::#{version_module}::ElementReqs
                  sd = #{namespace}::#{version_module}::SegmentDefs

                  InterchangeDef = Class.new(s::InterchangeDef) do
                    # @return [Values::InterchangeVal]
                    def empty(separators)
                      Stupidedi::Values::InterchangeVal.new(self, [], separators)
                    end

                    # @return [Module]
                    def segment_dict
                      #{namespace}::#{version_module}::SegmentDefs
                    end

                    # @return [Reader::Separators]
                    def separators(isa)
                      #{separators_method}
                    end

                    #{replace_separators_method}
                  end.new "#{interchange_version_code}",
                    [ sd::ISA.use(1, r::Mandatory, s::RepeatCount.bounded(1)),
                      sd::TA1.use(4, r::Optional,  s::RepeatCount.unbounded) ],
                    [ sd::IEA.use(5, r::Mandatory, s::RepeatCount.bounded(1)) ]

                end
              end
            end
          RUBY
        end
      end
    end
  end
end
