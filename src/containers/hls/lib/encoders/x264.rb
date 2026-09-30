# frozen_string_literal: true

require_relative "base"

module Hls
  module Encoders
    class X264 < Base
      def codec = "libx264"

      def speed = [["preset", "medium"]]

      # Any keyframe not in our list becomes an unwanted segment boundary.
      def keyframe_options = [["sc_threshold", "0"]]

      def all_idr_options = super + keyframe_options
    end
  end
end
