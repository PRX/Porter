# frozen_string_literal: true

module Hls
  # Reads the segments out of a media playlist.
  module MediaPlaylist
    # byterange: [length, offset], or nil without EXT-X-BYTERANGE (offset nil if omitted)
    Segment = Struct.new(:duration, :uri, :byterange)

    def self.segments(path)
      segments = []
      duration = byterange = nil
      File.foreach(path) do |line|
        line = line.strip
        if (m = line.match(/\A#EXTINF:([\d.]+)/))
          duration = m[1].to_f
        elsif (m = line.match(/\A#EXT-X-BYTERANGE:(\d+)(?:@(\d+))?/))
          byterange = [m[1].to_i, m[2]&.to_i]
        elsif duration && !line.empty? && !line.start_with?("#")
          segments << Segment.new(duration, line, byterange)
          duration = byterange = nil
        end
      end
      segments
    end

    # Each segment's end time, counted from 0.
    def self.boundaries(path)
      total = 0.0
      segments(path).map { |s| total += s.duration }
    end
  end
end
