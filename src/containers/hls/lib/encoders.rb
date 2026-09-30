# frozen_string_literal: true

require_relative "encoders/base"
require_relative "encoders/x264"
require_relative "encoders/videotoolbox"
require_relative "encoders/nvenc"

module Hls
  module Encoders
    BY_NAME = {
      "libx264" => X264,
      "videotoolbox" => VideoToolbox,
      "nvenc" => Nvenc
    }.freeze

    # nil when unset, so the caller falls back to the preset's default.
    # An unknown name raises
    def self.resolve(name)
      return nil if name.nil? || name.strip.empty?

      klass = BY_NAME[name.strip]
      if klass.nil?
        raise "unknown video encoder #{name.inspect}; expected one of " \
              "#{BY_NAME.keys.join(", ")}"
      end
      klass.new
    end
  end
end
