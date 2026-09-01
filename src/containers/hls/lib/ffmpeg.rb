# frozen_string_literal: true

module Hls
  # Builds the ffmpeg argument list for the whole package: one decode, fanned out
  # through filter_complex into three outputs across two muxers.
  #
  #   hls muxer      -> the video-only rungs, single_file + byteranges
  #   hls muxer      -> the trickplay stream, its own hls_time and I-frame GOP
  #   segment muxer  -> the audio rendition, split on an explicit time list
  #
  # Why different muxers? good question - check the README too.
  # TL;DR - the hls muxer has no explicit split-point option, so we make it split
  # at timed keyframes which we can set (each segment starts with a keyframe).
  # For audio-only, every frame is a keyframe, so hls muxer's `hls_time` alone would
  # lose the break.
  # Instead, we use the segment muxer for audio which honors -segment_times but has no
  # single-file mode, that's why we need TsPacker afterwards to make a single audio file.
  #
  # I know, it's weird to me too, I expected to just use hls for the audio variant, but
  # this is what I could figure out that works.
  #
  # The I-frame only variant makes keyframes every .5s, so it should be close enough for SSAI -
  # yeah, it's possible it could be up to .25s off, but for trickplay/scrubbing, that's fine and valid.
  class FFmpeg
    # rungs        -- [{height:, size:, bitrate:}] selected for this source
    # layout       -- Hls::Boundaries::Layout
    # settings     -- the preset
    # input        -- path to the downloaded artifact
    # dir          -- output directory
    # audio_parts  -- directory for the segment muxer's audio parts
    def initialize(input:, dir:, rungs:, layout:, settings:, audio_parts:)
      @input = input
      @dir = dir
      @rungs = rungs
      @layout = layout
      @s = settings
      @audio_parts = audio_parts
    end

    def command
      [
        "ffmpeg",
        "-hide_banner",
        ["-loglevel", "warning"],
        "-y",
        ["-i", @input],
        ["-filter_complex", filter_complex],
        video_output,
        trickplay_output,
        audio_output
      ].flatten
    end

    # Rungs taller than the source are skipped rather than upscaled.
    def self.select_rungs(all_rungs, source_height)
      selected = all_rungs.select { |r| r[:height] <= source_height }
      skipped = all_rungs.reject { |r| r[:height] <= source_height }.map { |r| r[:height] }
      [selected, skipped]
    end

    private

    def filter_complex
      labels = @rungs.map { |r| "[s_#{r[:height]}p]" }.join + "[s_iframe]"
      branches = @rungs.map do |r|
        scale_branch("s_#{r[:height]}p", r[:size], @s::FPS, "v_#{r[:height]}p")
      end
      # One extra branch for the trickplay stream
      branches << scale_branch("s_iframe", @s::IFRAME_SIZE, @s::IFRAME_FPS, "v_iframe")

      (["[0:v]split=#{@rungs.length + 1}#{labels}"] + branches).join(";")
    end

    # One branch of the split, normalized to a rung's size and rate.
    def scale_branch(input, size, fps, output)
      scale = [
        "scale=#{size}",
        # stops a non-16:9 source being stretched
        "force_original_aspect_ratio=decrease",
        # `H.264 4:2:0` cannot code an odd luma width
        "force_divisible_by=2",
        # always use the Lanczos scaling algorithm for the video resolution conversion
        "flags=lanczos"
      ].join(":")

      filters = [
        scale,
        # constant rate, which the frame-exact boundary math requires; a VFR
        # source otherwise gets breaks on frames that do not exist
        "fps=#{fps}",
        # square pixels, so coded size equals display size and RESOLUTION matches
        # what a validator reads from the SPS
        "setsar=1"
      ].join(",")

      "[#{input}]#{filters}[#{output}]"
    end

    def video_output
      maps = @rungs.map { |r| ["-map", "[v_#{r[:height]}p]"] }
      var_stream_map = @rungs.each_with_index.map { |r, i| "v:#{i},name:#{r[:height]}p" }.join(" ")

      encodes = @rungs.each_with_index.map do |rung, i|
        bitrate = rung[:bitrate]
        [
          ["-c:v:#{i}", "libx264"],
          ["-preset:v:#{i}", @s::PRESET],
          ["-profile:v:#{i}", "high"],
          # B-frame guidance for H.264 is 2-3.
          ["-bf:v:#{i}", "3"],
          ["-b:v:#{i}", bitrate],
          ["-maxrate:v:#{i}", bitrate],
          ["-bufsize:v:#{i}", "#{kbps(bitrate) * 2}k"],

          # An explicit list calculated in boundaries.rb
          ["-force_key_frames:v:#{i}", @layout.keyframes.join(",")],

          # Any keyframe not in our list becomes an unwanted segment boundary, so
          # scene-change detection is off and -g is deliberately unset
          # A uniform-cadence ladder could use -g; our boundaries are irregular by design.
          ["-sc_threshold:v:#{i}", "0"]
        ]
      end

      [
        maps,
        encodes,
        # Video rungs carry no audio: it is delivered once via an AUDIO group
        "-an",
        ["-pix_fmt", "yuv420p"],
        hls_muxer(hls_time: @s::HLS_TIME),
        # ffmpeg's own master playlist is discarded
        ["-master_pl_name", @s::FFMPEG_RAW_MASTER],
        ["-var_stream_map", var_stream_map],
        ["-hls_segment_filename", File.join(@dir, "%v.ts")],
        File.join(@dir, "%v.m3u8")
      ]
    end

    # I-frames-only output (i.e. trickplay)!
    # A separate hls output rather than another var_stream_map entry, because it
    # needs its own -hls_time and that is per-output.
    def trickplay_output
      # The rate cap is not optional: all-IDR content is spiky enough that an uncapped
      # encode peaks well over twice its own average, which gets flagged.
      cap = (kbps(@s::IFRAME_BITRATE) * @s::IFRAME_MAXRATE_FACTOR / 10.0).round
      [
        ["-map", "[v_iframe]"],
        "-an",
        ["-c:v", "libx264"],
        ["-preset:v", @s::PRESET],
        ["-profile:v", "high"],
        ["-pix_fmt", "yuv420p"],
        ["-b:v", @s::IFRAME_BITRATE],
        ["-maxrate", "#{cap}k"],
        ["-bufsize", "#{(cap / 2.0).round}k"],
        # -g 1 -keyint_min 1: every frame an IDR, which is what makes an
        # I-frames-only playlist possible at all. -sc_threshold 0 for consistency;
        # with -g 1 there is nothing left for scene detection to add.
        ["-g", "1"],
        ["-keyint_min", "1"],
        ["-sc_threshold", "0"],
        hls_muxer(hls_time: format("%.6f", 1.0 / @s::IFRAME_FPS)),
        ["-hls_segment_filename", File.join(@dir, @s::IFRAME_MEDIA)],
        File.join(@dir, @s::IFRAME_PLAYLIST)
      ]
    end

    # -segment_times takes the UNBIASED list: audio needs no encoder bias, because
    # every audio frame is a keyframe so there is no wrong frame to steer away
    # from. Feeding audio the biased list pushes it a frame early and roughly
    # doubles the drift at the splice (26ms observed, versus 8ms).
    #
    # -segment_time_delta 0 because there is no keyframe-snapping slop to absorb:
    # every audio frame is a candidate split point, so the muxer lands on the first
    # frame at or after each target. Residual drift versus video is bounded by one
    # AAC frame (1024 samples, 21.33ms at 48kHz).
    def audio_output
      [
        ["-map", "0:a:0"],
        ["-c:a", "aac"],
        ["-b:a", @s::AUDIO_BITRATE],
        # Forced, not inherited: a 5.1 source would otherwise stay 5.1 while the
        # master playlist declares CHANNELS from this same constant, so the
        # playlist would misdescribe the stream.
        ["-ac", @s::AUDIO_CHANNELS],
        ["-ar", @s::AUDIO_SAMPLE_RATE],
        ["-f", "segment"],
        ["-segment_times", @layout.audio_splits.join(",")],
        ["-segment_time_delta", "0"],
        ["-segment_format", "mpegts"],
        ["-segment_list", File.join(@audio_parts, "parts.m3u8")],
        ["-segment_list_type", "m3u8"],
        File.join(@audio_parts, "a%05d.ts")
      ]
    end

    # single_file emits one .ts plus EXT-X-BYTERANGE entries, so the origin has to
    # honor HTTP Range requests (S3 does).
    def hls_muxer(hls_time:)
      [
        ["-f", "hls"],
        ["-hls_time", hls_time.to_s],
        ["-hls_playlist_type", "vod"],
        ["-hls_list_size", "0"],
        ["-hls_segment_type", "mpegts"],
        ["-hls_flags", "single_file"]
      ]
    end

    # "2800k" -> 2800
    def kbps(bitrate)
      bitrate.to_s.delete_suffix("k").to_i
    end
  end
end
