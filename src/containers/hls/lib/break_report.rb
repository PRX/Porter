# frozen_string_literal: true

require_relative "media_playlist"
require_relative "timing"

module Hls
  # Maps each requested ad break onto the segment boundary it actually landed on.
  module BreakReport
    class << self
      include Timing

      # breaks: Boundaries::Break, or Edits::Placed which adds removed for a cut range
      #   e.g. [10, [20, 30]] which indicates a break at 10s and a cut from 20s to 30s.
      # playlist: any video rendition's media playlist; they are all
      #   boundary-identical by construction, so which one does not matter
      # tolerance: how far ActualTime may sit from the frame we asked for before
      #   that counts as the encoder ignoring the keyframe list.
      #
      # Raises when a break is requested but the encoder did not honor it
      def build(breaks, playlist, tolerance:)
        return [] if breaks.nil? || breaks.empty?

        boundaries = MediaPlaylist.boundaries(playlist)
        raise "#{playlist} has no segments to place breaks against" if boundaries.empty?

        breaks.map do |brk|
          wanted = brk.at.to_f
          index = closest_index(boundaries, wanted)
          landed = boundaries[index]

          if (landed - wanted).abs > tolerance
            raise "break #{requested_formatted(brk.requested).inspect} requested at #{round6(wanted)}s but the nearest is #{round6(landed)}s."
          end

          entry = {
            RequestedTime: requested_formatted(brk.requested),
            ActualTime: round6(landed),
            InsertAfterSegmentIndex: index
          }
          removed = brk.respond_to?(:removed) && brk.removed
          entry[:RemovedDuration] = round6(removed.to_f) if removed
          entry
        end
      end

      def requested_formatted(requested)
        return round6(requested.to_f) unless requested.is_a?(Array)
        requested.map { |t| t && round6(t.to_f) }
      end

      def closest_index(boundaries, wanted)
        boundaries.each_with_index.min_by { |b, _| (b - wanted).abs }.last
      end
    end
  end
end
