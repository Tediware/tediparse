# frozen_string_literal: true
module Stupidedi
  module Exceptions
    #
    # Raised by {Parser::Generation#read} when the number of rejected
    # segments exceeds the +:max_rejected_segments+ option.
    #
    class RejectedSegmentLimitError < ParseError
      # @return [Integer]
      attr_reader :count

      # @return [Values::InvalidSegmentVal]
      attr_reader :first

      def initialize(count, first)
        @count, @first = count, first

        super("stopped parsing after #{count} rejected segments; the first " \
              "was #{first.id} at #{first.position.inspect} (#{first.reason})")
      end
    end
  end
end
