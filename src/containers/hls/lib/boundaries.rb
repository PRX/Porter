# frozen_string_literal: true

require "json"

module Hls
  # Computes the segment-boundary layout for an asset with ad breaks.
  # Outputs the timings to be used in ffmpeg to generate audio and video segments
  # cut at the right places.
  #
  # This is a bit involved so I'm going to document the reasoning here -
  # some of this is in the README too, but this is more detailed, and specific to the code.

  # Ads can only be stitched into an HLS playlist *between* segments for SSAI.
  # Even for interstitials, you can specifiy a break inside a segment, but it's not preferred.
  # So every ad-break time must also be a segment boundary, and start with a keyframe.
  # When we know the break times before encoding, we can choose a segment layout/grid
  # that puts a boundary exactly where each break goes.

  # The ffmpeg `hls` muxer has no explicit split-point option, so we get there as best we can
  # with `force_key_frames` (video) and `segment_times` (audio).
  #
  # How the ffmpeg hls muxer actually works to decide on segments isn't really documented
  # -- this is from `hlsenc.c``, and confirmed by running it:
  # https://github.com/FFmpeg/FFmpeg/blob/master/libavformat/hlsenc.c
  #
  #     end_pts = hls->recording_time * vs->number;              // hls_write_packet
  #     ...
  #     if (vs->packets_written && can_split &&
  #         (av_rescale_q(pkt->pts, ...) - vs->start_pts >= end_pts)) {   // split
  #
  # `recording_time` is hls_time, `vs->number` is how many segments have been
  # written (pre-incremented to 1 in hls_write_header, so the first target is
  # hls_time, not 0), and `vs->start_pts` is the FIRST pts of the whole stream,
  # set once and never reset per segment. `can_split` additionally requires a
  # video keyframe and a strictly positive duration since the last boundary.
  #
  # So the threshold is CUMULATIVE -- hls_time * segments_so_far -- and not "how
  # long since the last boundary". The n-th split cannot happen before
  # n * hls_time.
  #
  # What this mean:
  #   - Short segments are fine. Once the stream is ahead of the cumulative
  #     target -- which it is almost immediately, since segments are ~target
  #     seconds long and the target only grows by hls_time -- the muxer splits at
  #     EVERY keyframe regardless of spacing. Measured: keyframes at 6.0 and 6.1
  #     with hls_time 2 produced a real 0.1s segment.
  #   - The final segment will be whatever is left, and is routinely shorter than
  #     hls_time. Measured: a 1.167s last segment with hls_time 2.
  #
  # So the only place the rule bites is near the START, before the stream has
  # outrun the target. We rely on two things:
  #   1. The only keyframes in the stream are at our boundaries
  #      (-force_key_frames <this list> plus -sc_threshold 0).
  #   2. Every boundary is reachable under the cumulative rule, which
  #      #unreachable_boundaries simulates exactly rather than approximating.
  #
  # Then "split at the first reachable keyframe" = "split at every keyframe", which is exactly our list.
  #
  # The audio rendition is a bit different b/c it is cut by the `segment` muxer,
  # whose `-segment_times` IS authoritative and will honor the list of times.
  #
  # `min_segment` is a separate idea (and a bit more aesthetic?).
  # When a break lands near a regular grid point we drop that point to make a bigger segment,
  # rather than emit a teeny tiny segment.
  module Boundaries
    # keyframes:    for -force_key_frames, b/c rounding difference are a half-frame-early
    # segments:     exact frame times -- the boundary list itself
    # audio_splits: for -segment_times, a half audio frame early for the same reason
    # breaks:       the requested ad breaks
    Layout = Struct.new(:keyframes, :segments, :audio_splits, :breaks)

    Break = Struct.new(:requested, :at)

    class << self
      # audio_grain is one audio frame in seconds (1024/48000 for AAC-LC at 48 kHz).
      def build(duration:, target:, fps:, hls_time:, breaks: [], max_seg: nil,
        min_segment: hls_time, audio_grain: nil)
        # no floats; all Rational for exact math and rounding
        duration = exact(duration)
        target = exact(target)
        fps = exact(fps)
        hls_time = exact(hls_time)
        min_segment = exact(min_segment)
        max_seg = max_seg.nil? ? target : exact(max_seg)

        # can't generate a valid grid if hls_time > target
        if hls_time > target
          raise "hls_time (#{hls_time.to_f}s) is longer than the segment target (#{target.to_f}s)"
        end

        requested = breaks.map { |b| [b, quantize_one(b, fps)] }

        # check for breaks that just won't work
        reject_unusable_breaks(requested, duration, fps)

        pairs = requested.sort_by(&:last)
        quantized = pairs.map(&:last)

        bounds = grid(target, duration)
        bounds = prune_near_breaks(bounds, quantized, min_segment)
        bounds = (bounds + quantized).uniq.sort
        bounds = drop_runts(bounds, quantized, duration, min_segment)
        bounds = cap_segment_length(bounds, duration, min_segment, max_seg)

        # finds boundaries that are not reachable by the hls muxer (see above)
        unreachable = unreachable_boundaries(bounds, hls_time)
        unless unreachable.empty?
          raise "boundaries #{unreachable.map { |b| fmt(b) }.join(", ")} are not reachable by the hls muxer."
        end

        # check to make sure we still have the breaks after all the prune and dropping
        missing = pairs.reject { |_, q| bounds.include?(q) }
        unless missing.empty?
          raise "breaks #{missing.map { |_, q| fmt(q) }.join(", ")} were removed from the layout."
        end

        # subtract half a frame so hls_time will snap to the next frame.
        # prevents differences in rounding from causing it to be one past
        half = Rational(1, 2 * fps)
        keyframes = bounds.map { |b| quantized.include?(b) ? b - half : b }

        # the segment muxer cuts at the first audio frame at or after the time given,
        # so biasing by half a frame turns that into the nearest frame to the boundary
        half_audio = audio_grain.nil? ? Rational(0) : exact(audio_grain) / 2
        audio_splits = bounds.map { |b| b - half_audio }

        Layout.new(
          keyframes: keyframes.map { |b| fmt(b) },
          segments: bounds.map { |b| fmt(b) },
          audio_splits: audio_splits.map { |b| fmt(b) },
          breaks: pairs.map { |req, q| Break.new(requested: req, at: fmt(q)) }
        )
      end

      # Break times from a multi-part source, where the joins between parts are the breaks.
      #
      # Accumulates integer frame counts rather than float durations, and quantizes
      # each part against its own rate, so mixed-rate parts still give exact times.
      #
      # n.b. unused at the moment, as Porter accepts single file input, but tried it out.
      def from_part_durations(parts)
        cumulative = Rational(0)
        joins = parts.map do |part|
          fps = exact(part.fetch(:fps))
          frames = (exact(part.fetch(:duration)) * fps).round
          cumulative += Rational(frames) / fps
          cumulative
        end

        # The final join is the end of the asset, not an ad break.
        {breaks: joins[0..-2].map { |t| fmt(t) }, total: fmt(joins.last)}
      end

      private

      # reject if < 0, or past duration - 1 frame
      # reject if 2 breaks are closer than one frame apart
      def reject_unusable_breaks(requested, duration, fps)
        outside = requested.select { |_, q| q <= 0 || q >= duration }
        unless outside.empty?
          detail = outside.map { |req, q|
            (exact(req) == q) ? req.to_s : "#{req} (snaps to #{fmt(q)})"
          }.join(", ")
          raise "ad breaks #{detail} have to be > 0 and before #{fmt(duration)} duration (with >= 1 frame after)."
        end

        collided = requested.group_by(&:last).select { |_, g| g.length > 1 }
        unless collided.empty?
          detail = collided.map { |q, g|
            "#{g.map(&:first).join(" and ")} all land on frame time #{fmt(q)}"
          }.join("; ")
          raise "ad breaks collide after quantization: #{detail}. A frame is #{fmt(Rational(1, fps))}s, so breaks closer together than that can't be told apart."
        end
      end

      def grid(step, duration)
        out = []
        t = step
        while t < duration
          out << t
          t += step
        end
        out
      end

      # drop grid points too close to a break
      def prune_near_breaks(bounds, breaks, min_segment)
        bounds.reject { |g| breaks.any? { |b| (g - b).abs < min_segment } }
      end

      # Boundaries the hls muxer will skip, by simulating its cumulative target
      # (documented more at the top of the file and in the readme)
      def unreachable_boundaries(bounds, step)
        target = step
        bounds.reject do |b|
          reachable = b >= target
          target += step if reachable
          reachable
        end
      end

      # Keep grid points min_segment clear of the head and tail, so the first and last segments are not runts.
      def drop_runts(bounds, breaks, duration, min_segment)
        bounds.select do |x|
          breaks.include?(x) || (x >= min_segment && duration - x >= min_segment)
        end
      end

      # add back segment breaks where they are too long, after pruning and other adjustments
      def cap_segment_length(bounds, duration, min_segment, max_seg)
        edges = [Rational(0)] + bounds + [duration]
        additions = []

        edges.each_cons(2) do |lo, hi|
          gap = hi - lo
          next if gap <= max_seg

          # Fewest equal parts that all come in at or under max_seg...
          parts = (gap / max_seg).ceil
          # ...but never so many that a part drops below min_segment.
          parts = [1, (gap / min_segment).floor].max if gap / parts < min_segment

          if parts < 2
            puts JSON.dump({
              msg: "WARNING: segment is over the max_seg cap, but cannot be split without going under min_segment",
              from: fmt(lo), to: fmt(hi), length: fmt(gap),
              max_seg: max_seg.to_f, min_segment: min_segment.to_f
            })
            next
          end

          step = gap / parts
          if step > max_seg
            puts JSON.dump({
              msg: "WARNING: split segment is still over the max_seg cap",
              from: fmt(lo), to: fmt(hi), parts: parts,
              part_length: fmt(step), max_seg: max_seg.to_f
            })
          end
          (1...parts).each { |i| additions << lo + step * i }
        end

        additions.empty? ? bounds : (bounds + additions).uniq.sort
      end

      def exact(value)
        Rational(value.to_s)
      end

      def quantize_one(break_time, fps)
        b = exact(break_time)
        Rational((b * fps).round) / fps
      end

      def fmt(rational)
        format("%.6f", rational)
      end
    end
  end
end
