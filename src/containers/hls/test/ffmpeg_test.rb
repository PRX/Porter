# frozen_string_literal: true

# Argument construction only -- nothing is executed. Run: make test
require "minitest/autorun"
require_relative "../lib/ffmpeg"
require_relative "../lib/boundaries"

module FFmpegTestSettings
  FPS = "30"
  HLS_TIME = 2
  PRESET = "medium"
  AUDIO_BITRATE = "192k"
  AUDIO_SAMPLE_RATE = "48000"
  AUDIO_CHANNELS = "2"
  IFRAME_FPS = 2
  IFRAME_SIZE = "426x240"
  IFRAME_BITRATE = "150k"
  IFRAME_MAXRATE_FACTOR = 15
  IFRAME_PLAYLIST = "iframe.m3u8"
  IFRAME_MEDIA = "iframe.ts"
  FFMPEG_RAW_MASTER = "ffmpeg-raw.m3u8"
end

FFMPEG_TEST_RUNGS = [
  {height: 1080, size: "1920x1080", bitrate: "5000k"},
  {height: 720, size: "1280x720", bitrate: "2800k"},
  {height: 480, size: "854x480", bitrate: "1200k"}
].freeze

describe Hls::FFmpeg do
  def layout(breaks: [90.5])
    Hls::Boundaries.build(duration: 300.0, target: 6, fps: "30", hls_time: 2, breaks: breaks)
  end

  def cmd(rungs: FFMPEG_TEST_RUNGS, breaks: [90.5])
    Hls::FFmpeg.new(input: "artifact.file", dir: "out", rungs: rungs,
      layout: layout(breaks: breaks), settings: FFmpegTestSettings,
      audio_parts: "out/_audio_parts").command
  end

  # Value that follows a given flag.
  def value_after(list, flag)
    i = list.index(flag)
    i && list[i + 1]
  end

  describe ".select_rungs" do
    it "keeps rungs at or below the source height" do
      selected, skipped = Hls::FFmpeg.select_rungs(FFMPEG_TEST_RUNGS, 1080)
      _(selected.map { |r| r[:height] }).must_equal [1080, 720, 480]
      _(skipped).must_equal []
    end

    it "drops rungs taller than the source rather than upscaling" do
      selected, skipped = Hls::FFmpeg.select_rungs(FFMPEG_TEST_RUNGS, 720)
      _(selected.map { |r| r[:height] }).must_equal [720, 480]
      # Returned, not discarded: a target may require the variant that got
      # skipped, so the caller has to be able to say which ones those were.
      _(skipped).must_equal [1080]
    end

    it "can drop everything, so the caller can fail loudly" do
      selected, skipped = Hls::FFmpeg.select_rungs(FFMPEG_TEST_RUNGS, 240)
      _(selected).must_equal []
      _(skipped).must_equal [1080, 720, 480]
    end
  end

  describe "the filter graph" do
    it "splits once for every rung plus the trickplay branch" do
      fc = value_after(cmd, "-filter_complex")
      _(fc).must_match(/\A\[0:v\]split=4/)
      _(fc).must_include "[s_1080p]"
      _(fc).must_include "[s_iframe]"
    end

    it "normalizes frame rate on every branch" do
      fc = value_after(cmd, "-filter_complex")
      _(fc.scan("fps=30").length).must_equal 3
      # I-frame-only/trickplay, its own much lower rate
      _(fc).must_include "fps=2"
    end

    it "sets square pixels and even dimensions on every branch" do
      fc = value_after(cmd, "-filter_complex")
      _(fc.scan("setsar=1").length).must_equal 4
      _(fc.scan("force_divisible_by=2").length).must_equal 4
      _(fc.scan("force_original_aspect_ratio=decrease").length).must_equal 4
    end

    it "keeps the lanczos scaler the container already used" do
      _(value_after(cmd, "-filter_complex").scan("flags=lanczos").length).must_equal 4
    end
  end

  describe "keyframe conditioning" do
    it "gives every rung its own -force_key_frames, not just the first" do
      c = cmd
      3.times { |i| _(c).must_include "-force_key_frames:v:#{i}" }
      _(c).wont_include "-force_key_frames"
    end

    it "passes the biased keyframe list, identical for every rung" do
      c = cmd
      expected = layout.keyframes.join(",")
      3.times { |i| _(value_after(c, "-force_key_frames:v:#{i}")).must_equal expected }
      # the break is half a frame early in this list
      _(expected).must_include "90.483333"
    end

    it "passes a literal list rather than an expr" do
      _(value_after(cmd, "-force_key_frames:v:0")).wont_include "expr:"
    end

    it "suppresses scene-change keyframes per stream" do
      c = cmd
      3.times { |i| _(value_after(c, "-sc_threshold:v:#{i}")).must_equal "0" }
    end

    it "never sets -g on a video rung" do
      # A -g landing off our boundary list adds its own IDRs, and a stray keyframe
      # becomes an unwanted segment boundary.
      c = cmd
      3.times { |i| _(c).wont_include "-g:v:#{i}" }
      # the trickplay stream is the one place -g belongs, at 1
      _(value_after(c, "-g")).must_equal "1"
    end
  end

  describe "the video output" do
    it "carries no audio" do
      _(cmd).must_include "-an"
    end

    it "declares one variant per rung, named by height" do
      _(value_after(cmd, "-var_stream_map"))
        .must_equal "v:0,name:1080p v:1,name:720p v:2,name:480p"
    end

    it "uses single_file without independent_segments" do
      _(value_after(cmd, "-hls_flags")).must_equal "single_file"
    end

    it "sets bufsize to twice the target bitrate" do
      _(value_after(cmd, "-bufsize:v:0")).must_equal "10000k"
      _(value_after(cmd, "-bufsize:v:2")).must_equal "2400k"
    end

    it "writes ffmpeg's master to a throwaway name" do
      _(value_after(cmd, "-master_pl_name")).must_equal "ffmpeg-raw.m3u8"
    end
  end

  describe "the trickplay output" do
    it "makes every frame an IDR" do
      c = cmd
      _(value_after(c, "-g")).must_equal "1"
      _(value_after(c, "-keyint_min")).must_equal "1"
    end

    it "sets hls_time to the frame interval so each frame is its own segment" do
      # two hls outputs: the ladder at HLS_TIME, then trickplay at 1/IFRAME_FPS
      c = cmd
      times = c.each_index.select { |i| c[i] == "-hls_time" }.map { |i| c[i + 1] }
      _(times).must_equal ["2", "0.500000"]
    end

    it "rate caps the encode at the configured factor" do
      # All-IDR content is spiky enough that an uncapped encode gets flagged.
      _(value_after(cmd, "-maxrate")).must_equal "225k"   # 150k * 1.5
      _(value_after(cmd, "-bufsize")).must_equal "113k"
    end
  end

  describe "the audio output" do
    it "uses the segment muxer with an explicit split list" do
      c = cmd
      _(value_after(c, "-f")).must_equal "hls"          # first -f is the ladder
      _(c).must_include "segment"
      _(value_after(c, "-segment_times")).must_equal layout.audio_splits.join(",")
    end

    it "passes the UNBIASED list, unlike video" do
      _(value_after(cmd, "-segment_times")).must_include "90.500000"
      _(value_after(cmd, "-segment_times")).wont_include "90.483333"
    end

    it "sets segment_time_delta to zero" do
      _(value_after(cmd, "-segment_time_delta")).must_equal "0"
    end

    it "does not reset timestamps" do
      # One continuous timeline across the file, not each part restarting at zero.
      _(cmd).wont_include "-reset_timestamps"
    end

    it "encodes at the preset's audio bitrate" do
      _(value_after(cmd, "-b:a")).must_equal "192k"
      _(value_after(cmd, "-ar")).must_equal "48000"
    end

    it "forces the channel count the master playlist declares" do
      _(value_after(cmd, "-ac")).must_equal FFmpegTestSettings::AUDIO_CHANNELS
    end
  end

  describe "shape" do
    it "decodes the input exactly once" do
      _(cmd.count("-i")).must_equal 1
    end

    it "produces a flat array of strings" do
      c = cmd
      _(c).must_be_instance_of Array
      _(c.all?(String)).must_equal true
      _(c.first).must_equal "ffmpeg"
    end

    it "adapts to a reduced rung set" do
      c = cmd(rungs: FFMPEG_TEST_RUNGS.last(1))
      _(value_after(c, "-filter_complex")).must_match(/split=2/)
      _(value_after(c, "-var_stream_map")).must_equal "v:0,name:480p"
      _(c).wont_include "-force_key_frames:v:1"
    end

    it "still works with no breaks at all" do
      c = cmd(breaks: [])
      _(value_after(c, "-force_key_frames:v:0")).must_include "6.000000"
      _(value_after(c, "-segment_times")).must_include "12.000000"
    end
  end
end
