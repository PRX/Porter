# frozen_string_literal: true

require_relative "base"

module Hls
  module Encoders
    class Nvenc < Base
      def codec = "h264_nvenc"

      def input_flags = ["-hwaccel", "cuda", "-hwaccel_output_format", "cuda"]

      def speed = [["preset", "p4"]]

      # -sc_threshold is x264-only and silently does nothing here. Without these,
      # nvenc adds I-frames at scene cuts and may emit a forced keyframe as non-IDR.
      def keyframe_options = [["forced-idr", "1"], ["no-scenecut", "1"]]

      def all_idr_options = super + keyframe_options

      # Frames are already in cuda format; naming a pixel format downloads them.
      def pix_fmt = nil

      # scale_npp matches the software chain, lanczos included;
      # reset_sar replaces setsar=1.
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
  end
end
