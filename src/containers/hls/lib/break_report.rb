# frozen_string_literal: true

module Hls
  # Maps each requested ad break onto the segment boundary it actually landed on.
  module BreakReport
    class << self
      # breaks: Boundaries::Break values
      # playlist: any video rendition's media playlist; they are all
      #   boundary-identical by construction, so which one does not matter
      # tolerance: how far ActualTime may sit from the frame we asked for before
      #   that counts as the encoder ignoring the keyframe list.
      #
      # Raises when a break is requested but the encoder did not honor it
      def build(breaks, playlist, tolerance:)
        return [] if breaks.nil? || breaks.empty?

        boundaries = cumulative_boundaries(playlist)
        raise "#{playlist} has no segments to place breaks against" if boundaries.empty?

        breaks.map do |brk|
          wanted = brk.at.to_f
          index = closest_index(boundaries, wanted)
          landed = boundaries[index]

          if (landed - wanted).abs > tolerance
            raise "break #{brk.requested} requested at #{round6(wanted)}s but the nearest is #{round6(landed)}s."
          end

          {
            RequestedTime: round6(brk.requested.to_f),
            ActualTime: round6(landed),
            InsertAfterSegmentIndex: index
          }
        end
      end

      private

      # Running total of EXTINF durations
      def cumulative_boundaries(playlist)
        total = 0.0
        out = []
        File.foreach(playlist) do |line|
          next unless (m = line.match(/\A#EXTINF:([\d.]+)/))
          total += m[1].to_f
          out << total
        end
        out
      end

      def closest_index(boundaries, wanted)
        boundaries.each_with_index.min_by { |b, _| (b - wanted).abs }.last
      end

      # Matches how boundary times are expressed everywhere else.
      def round6(value)
        value.round(6)
      end
    end
  end
end
