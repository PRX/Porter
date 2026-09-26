# frozen_string_literal: true

module Hls
  # What differs between video encoders. Option names come back without a stream
  # specifier; only the caller knows whether a flag is per-rung or per-output.
  module Encoders
    class Base
      def codec = raise NotImplementedError

      def input_flags = []

      def speed = []

      def keyframe_options = []

      def pix_fmt = "yuv420p"

      def b_frames = "3"

      def extra_flags = []

      def rate_control(bitrate:, bufsize:)
        [["b", bitrate], ["maxrate", bitrate], ["bufsize", bufsize]]
      end

      # Separate from the rungs': all-IDR content is spiky, so the goal here is
      # bounding the peak rather than quality per bit.
      def trickplay_rate_control(bitrate:, cap:, bufsize:)
        [["b", bitrate], ["maxrate", cap], ["bufsize", bufsize]]
      end

      # Checked before encoding, so a task on the wrong instance fails immediately.
      def available? = true

      def unavailable_reason = nil

      # Its own set: a profile's keyframe_options may carry a long -g that would
      # override this -g 1.
      def all_idr_options = [["g", "1"], ["keyint_min", "1"]]

      # Square pixels, even luma width, no stretching, and the constant rate the
      # frame-exact boundary math depends on.
      def scale_filters(size:, fps:)
        scale = [
          "scale=#{size}",
          "force_original_aspect_ratio=decrease",
          "force_divisible_by=2",
          "flags=lanczos"
        ].join(":")

        [scale, "fps=#{fps}", "setsar=1"].join(",")
      end
    end

    class X264 < Base
      def codec = "libx264"

      def speed = [["preset", "medium"]]

      # Any keyframe not in our list becomes an unwanted segment boundary.
      def keyframe_options = [["sc_threshold", "0"]]

      def all_idr_options = super + keyframe_options
    end

    # Apple Silicon. scale_vt has no aspect-ratio or interpolation options, so
    # scaling stays in software and only the encode moves.
    class VideoToolbox < Base
      def codec = "h264_videotoolbox"

      def available? = RUBY_PLATFORM.include?("darwin")

      def unavailable_reason = "VideoToolbox needs macOS; this is #{RUBY_PLATFORM}"

      # B-frame reordering jitters output timestamps by ~11us, which the validator
      # reports as MUST-fix 535009. Costs some compression efficiency.
      def b_frames = "0"

      # Constrained VBR with the ceiling ABOVE the average. maxrate == b:v starves
      # this encoder to 68% of the requested rate, with visible artifacts on fast
      # motion; a 1.5x ceiling gets 96% and still bounds the peak.
      def rate_control(bitrate:, bufsize:)
        ceiling = (bitrate.to_s.sub(/k\z/, "").to_i * 1.5).round
        [["b", bitrate], ["maxrate", "#{ceiling}k"], ["bufsize", bufsize]]
      end

      # CBR keeps the peak closest to the average, but cannot reach the 2x that
      # validator 235045 wants, and nothing can: each trickplay segment is a single
      # I-frame, so there is no window to smooth across and the ratio is just
      # largest frame over mean (3.94x here, 1.43x for x264). This profile trips
      # that SHOULD on the trickplay variant by construction.
      def trickplay_rate_control(bitrate:, cap:, bufsize:)
        [["b", bitrate], ["constant_bit_rate", "1"]]
      end

      # No -sc_threshold here, and left alone it inserts keyframes aggressively (78
      # in a 30s clip), each an unplanned segment boundary. A GOP longer than any
      # segment we author leaves only the forced list: 1200 frames is 40s at 30fps,
      # past the 10s TARGETDURATION ceiling.
      def keyframe_options = [["g", "1200"]]
    end

    # Frames stay on the GPU from decode through scale to encode.
    class Nvenc < Base
      def codec = "h264_nvenc"

      def input_flags = ["-hwaccel", "cuda", "-hwaccel_output_format", "cuda"]

      # ECS exposes the GPU as device nodes; an encoder compiled into ffmpeg proves
      # nothing about the hardware.
      def available? = !Dir.glob("/dev/nvidia*").empty?

      def unavailable_reason = "no /dev/nvidia* device; this needs a GPU instance"

      def speed = [["preset", "p4"]]

      # -sc_threshold is x264-only and silently does nothing here. Without these,
      # nvenc adds I-frames at scene cuts and may emit a forced keyframe as non-IDR.
      def keyframe_options = [["forced-idr", "1"], ["no-scenecut", "1"]]

      def all_idr_options = super + keyframe_options

      # Frames are already in cuda format; naming a pixel format downloads them.
      def pix_fmt = nil

      # scale_npp matches the software chain, lanczos included; reset_sar replaces
      # setsar=1.
      def scale_filters(size:, fps:)
        width, height = size.split("x")
        scale = [
          "scale_npp=w=#{width}:h=#{height}",
          "force_original_aspect_ratio=decrease",
          "force_divisible_by=2",
          "interp_algo=lanczos",
          "reset_sar=1"
        ].join(":")

        [scale, "fps=#{fps}"].join(",")
      end
    end

    BY_NAME = {
      "libx264" => X264,
      "videotoolbox" => VideoToolbox,
      "nvenc" => Nvenc
    }.freeze

    # nil when unset, so the caller falls back to the preset's default. An unknown
    # name raises, so a typo fails the job instead of quietly encoding on the CPU.
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
