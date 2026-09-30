# frozen_string_literal: true

require "open3"

module Hls
  module Encoders
    class Base
      def codec = raise NotImplementedError

      def input_flags = []

      def speed = []

      def keyframe_options = []

      def pix_fmt = "yuv420p"

      def b_frames = "3"

      def extra_flags = []

      # in other encoders, passing in height lets a profile tune per rung (without actually passing in the rung)
      def rate_control(bitrate:, bufsize:, height:)
        [["b", bitrate], ["maxrate", bitrate], ["bufsize", bufsize]]
      end

      # Checked before encoding, so a task on the wrong instance fails immediately.
      # A tenth of a second through this encoder with the rungs' options proves the
      # ffmpeg build, the hardware and those options all work here.
      def available? = probe_failure.nil?

      def unavailable_reason = probe_failure

      # IDR options are only used for the trickplay stream
      # encoders (so far) add on to this list, but could override entirely
      def all_idr_options = [["g", "1"], ["keyint_min", "1"]]

      # Likely not ideal for smallest files or fastest encoding, but...
      # square pixels, even luma width, no stretching, and the constant rate
      # are what the frame-exact boundary math depends on.
      def scale_filters(size:, fps:)
        scale = [
          "scale=#{size}",
          "force_original_aspect_ratio=decrease",
          "force_divisible_by=2",
          "flags=lanczos"
        ].join(":")

        [scale, "fps=#{fps}", "setsar=1"].join(",")
      end

      private

      def probe_failure
        return @_probe_failure if defined?(@_probe_failure)
        @_probe_failure = missing_encoder || encode_failure
      end

      # just check the ffmpeg build for the encoder support
      def missing_encoder
        stdout, _stderr, _status = Open3.capture3("ffmpeg", "-hide_banner", "-encoders")
        built = stdout.lines.drop_while { |l| !l.start_with?(" ------") }.drop(1).map { |l| l.split[1] }
        "this ffmpeg is not built with #{codec}" unless built.include?(codec)
      end

      # do a teeny tiny encode to see if the encoder is actually working,
      # and that typical options we pass in are accepted (it's quick & definitive)
      def encode_failure
        _stdout, stderr, status = Open3.capture3(*probe_command)
        # An option this encoder does not take is only a warning, and ffmpeg still exits 0.
        ignored = stderr.lines.grep(/has not been used for any stream/)
        if !status.success?
          stderr.strip.empty? ? "ffmpeg exited #{status.exitstatus}" : stderr.split.join(" ")
        elsif ignored.any?
          ignored.map(&:strip).join(" ")
        end
      end

      def probe_command
        opts = speed + rate_control(bitrate: "1000k", bufsize: "2000k", height: 480) +
          keyframe_options + extra_flags + [["bf", b_frames]]
        opts += [["pix_fmt", pix_fmt]] if pix_fmt
        ["ffmpeg", "-hide_banner", "-loglevel", "warning",
          "-f", "lavfi", "-i", "color=size=256x256:rate=30:duration=0.1",
          "-c:v", codec, *opts.flat_map { |name, value| ["-#{name}", value] },
          "-f", "null", "-"]
      end
    end
  end
end
