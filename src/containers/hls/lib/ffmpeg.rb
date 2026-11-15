# frozen_string_literal: true

require_relative "timing"

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
    # Seconds added to every output's timestamps. Encoders start below zero (AAC by its
    # priming samples, x264 by its B-frame delay) and each muxer would otherwise shift
    # its own stream up to zero by a different amount, putting audio and video out of
    # sync. The same offset on every output keeps them above zero, so nothing shifts.
    TS_OFFSET = "1"

    # rungs        -- [{height:, size:, bitrate:}] selected for this source
    # layout       -- Hls::Boundaries::Layout
    # settings     -- the preset
    # input        -- path to the downloaded artifact
    # dir          -- output directory
    # audio_parts  -- directory for the segment muxer's audio parts
    # encoder -- an Hls::Encoders profile; defaults to the preset's
    # keep         -- source spans to keep, [start, end] in seconds, end nil for the end;
    #                 nil cuts nothing
    def initialize(input:, dir:, rungs:, layout:, settings:, audio_parts:, encoder: nil, keep: nil)
      @input = input
      @dir = dir
      @rungs = rungs
      @layout = layout
      @s = settings
      @audio_parts = audio_parts
      @enc = encoder || settings::VIDEO_ENCODER.new
      @keep = keep
    end

    def command
      [
        "ffmpeg",
        "-hide_banner",
        ["-loglevel", "warning"],
        "-y",
        @enc.input_flags,
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

      video = @keep ? "[vcut]" : "[0:v]"
      (cut_stage + ["#{video}split=#{@rungs.length + 1}#{labels}"] + branches).join(";")
    end

    # Removes the AdBreaks ranges from video and audio before anything else sees them,
    # so every rung, trickplay and the audio rendition share one edited timeline.
    #
    # trim gets cut points as frame and sample counts, not seconds: fps sets the video
    # time base to one frame, and aresample sets the audio's to one sample, so a cut at
    # 12.533333s is start_pts=376 (30fps) and start_pts=601600 (48kHz). Seconds would
    # need decimals, and setpts=PTS-0.666667/TB can give two frames the same pts.
    # concat lays each span after the last, so spans are rebased to start at 0 -- by
    # their own source start, which also keeps the source's A/V offset in the first span.
    def cut_stage
      return [] unless @keep

      fps = Rational(@s::FPS)
      rate = Integer(@s::AUDIO_SAMPLE_RATE)
      n = @keep.length
      stage = [
        "[0:v]fps=#{@s::FPS},split=#{n}#{(0...n).map { |i| "[c#{i}]" }.join}",
        "[0:a:0]aresample=#{rate},asplit=#{n}#{(0...n).map { |i| "[d#{i}]" }.join}"
      ]
      @keep.each_with_index do |(from, to), i|
        first_frame = frame_index(from, fps)
        first_sample = (from * rate).round
        video = "trim=start_pts=#{first_frame}"
        audio = "atrim=start_pts=#{first_sample}"
        if to
          video += ":end_pts=#{frame_index(to, fps)}"
          audio += ":end_pts=#{(to * rate).round}"
        end
        stage << "[c#{i}]#{video},setpts=PTS-#{first_frame}[k#{i}]"
        stage << "[d#{i}]#{audio},asetpts=PTS-#{first_sample}[e#{i}]"
      end
      stage << "#{(0...n).map { |i| "[k#{i}][e#{i}]" }.join}concat=n=#{n}:v=1:a=1[vcut][acut]"
    end

    # Edits quantizes to frames, so anything else is a bug upstream, not a rounding choice.
    def frame_index(time, fps)
      frames = time * fps
      raise "cut at #{time.to_f}s is not on the #{@s::FPS}fps frame grid" unless frames.denominator == 1
      frames.to_i
    end

    # One branch of the split, normalized to a rung's size and rate.
    def scale_branch(input, size, fps, output)
      "[#{input}]#{@enc.scale_filters(size: size, fps: fps)}[#{output}]"
    end

    # Profile options carry no stream specifier; only the caller knows whether a
    # flag is per-rung (:v:0) or per-output (:v).
    def specified(pairs, spec)
      pairs.map { |name, value| ["-#{name}#{spec}", value] }
    end

    def pix_fmt_flags
      @enc.pix_fmt ? ["-pix_fmt", @enc.pix_fmt] : []
    end

    def video_output
      maps = @rungs.map { |r| ["-map", "[v_#{r[:height]}p]"] }
      var_stream_map = @rungs.each_with_index.map { |r, i| "v:#{i},name:#{r[:height]}p" }.join(" ")

      encodes = @rungs.each_with_index.map do |rung, i|
        rate_control = @enc.rate_control(
          bitrate: rung[:bitrate],
          bufsize: "#{kbps(rung[:bitrate]) * 2}k",
          height: rung[:height]
        )
        [
          ["-c:v:#{i}", @enc.codec],
          specified(@enc.speed, ":v:#{i}"),
          ["-profile:v:#{i}", "high"],
          ["-bf:v:#{i}", @enc.b_frames],
          specified(rate_control, ":v:#{i}"),
          # An explicit list calculated in boundaries.rb
          ["-force_key_frames:v:#{i}", @layout.keyframes.join(",")],

          # Whatever the encoder needs so the only keyframes are the ones above.
          # -g is deliberately unset: a uniform-cadence ladder could use it, but
          # our boundaries are irregular by design.
          specified(@enc.keyframe_options, ":v:#{i}"),
          specified(@enc.extra_flags, ":v:#{i}")
        ]
      end

      [
        maps,
        encodes,
        # Video rungs carry no audio: it is delivered once via an AUDIO group
        "-an",
        pix_fmt_flags,
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
        ["-c:v", @enc.codec],
        specified(@enc.speed, ":v"),
        ["-profile:v", "high"],
        pix_fmt_flags,
        ["-b:v", @s::IFRAME_BITRATE],
        ["-maxrate:v", "#{cap}k"],
        ["-bufsize:v", "#{(cap / 2.0).round}k"],
        # every frame an IDR, which is what makes an I-frames-only playlist possible
        specified(@enc.all_idr_options, ""),
        hls_muxer(hls_time: Timing.fmt(Rational(1, @s::IFRAME_FPS))),
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
    # frame at or after each target, counted from its first packet. Boundaries biases
    # the targets so that is the frame nearest each video boundary, within half an
    # AAC frame (512 samples, 10.67ms at 48kHz).
    def audio_output
      [
        ["-map", @keep ? "[acut]" : "0:a:0"],
        ["-c:a", "aac"],
        ["-b:a", @s::AUDIO_BITRATE],
        # Forced, not inherited: a 5.1 source would otherwise stay 5.1 while the
        # master playlist declares CHANNELS from this same constant, so the
        # playlist would misdescribe the stream.
        ["-ac", @s::AUDIO_CHANNELS],
        ["-ar", @s::AUDIO_SAMPLE_RATE],
        ["-f", "segment"],
        # The offset goes on the inner mpegts muxer: the segment muxer times its list
        # from zero, so an offset on it would be added to the first part's duration.
        ["-avoid_negative_ts", "disabled"],
        ["-segment_format_options", "output_ts_offset=#{TS_OFFSET}"],
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
        ["-output_ts_offset", TS_OFFSET],
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
