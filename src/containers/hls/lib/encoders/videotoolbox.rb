# frozen_string_literal: true

require_relative "base"

module Hls
  module Encoders
    # Apple Silicon scale_vt has no aspect-ratio or interpolation options, so only the encode moves.
    # for future me, tested prio_speed, spatial_aq and max_ref_frames and they made no difference
    class VideoToolbox < Base
      def codec = "h264_videotoolbox"

      # B-frame reordering jitters output timestamps by ~11us, which the validator
      # reports as MUST-fix 535009. Costs some compression efficiency.
      def b_frames = "0"

      # It seems like maxrate is a hard byte limit over every one-second window, and bufsize is never read.
      # Set too low, it starved the frames around each forced IDR; at 4x it only trims the worst peaks.
      # The qmax ceiling is what keeps hard frames from breaking up.
      # It is looser below 720p, where 36 pushed 480p's peak past twice its average (validator 235045)
      # (That's why height now gets passed in, to adjust qmax based on the rung)
      def rate_control(bitrate:, bufsize:, height:)
        ceiling = bitrate.to_s.delete_suffix("k").to_i * 4
        qmax = (height >= 720) ? "36" : "40"
        [["b", bitrate], ["maxrate", "#{ceiling}k"], ["qmax", qmax]]
      end

      # -g is max keyframe interval, and we only want keyframes where we explictly place them
      # Anything longer than our longest segment leaves only the forced list:
      # 1200 frames is 40s at 30fps, well past the 10s ceiling.
      def keyframe_options = [["g", "1200"]]
    end
  end
end
