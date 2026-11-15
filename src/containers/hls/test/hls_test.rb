# frozen_string_literal: true

require "minitest/autorun"
require "fileutils"
require "json"
require "open3"
require "tmpdir"
require_relative "harness/task_runner"
require_relative "../lib/media_playlist"

describe "hls.rb" do
  def self.preset_name = "Standard Podcast 2026 v1"

  def preset_name = self.class.preset_name

  def self.source = File.expand_path("samples/source-480p-13s.mp4", __dir__)

  def run_task(breaks: [], preset: preset_name, source: self.class.source, **opts)
    TaskRunner.run(
      source: source,
      task: {
        "Type" => "HLS",
        "Preset" => preset,
        "AdBreaks" => breaks
      },
      **opts
    )
  end

  def logged(run, msg)
    # The backtrace is plain text; every other log line is one JSON object.
    run.output.lines.grep(/\A\{/).map { |l| JSON.parse(l) }.find { |l| l["msg"] == msg }
  end

  # A real directory per shared encode, so assertions can read the bytes a client would fetch.
  def self.out_dir(name)
    (@out_dirs ||= {})[name] ||= Dir.mktmpdir("hls-test-#{name}").tap do |d|
      Minitest.after_run { FileUtils.remove_entry(d) }
    end
  end

  describe "input validation" do
    it "refuses a preset it does not implement" do
      run = run_task(preset: "Some Other Preset")
      _(run.ok?).must_equal false
      _(run.failure[:cause]).must_match(/Unsupported preset/)
    end

    it "refuses a negative ad break" do
      run = run_task(breaks: [-1.0])
      _(run.ok?).must_equal false
      _(run.failure[:cause]).must_match(/AdBreaks must be positive/)
    end

    it "refuses a non-numeric ad break" do
      run = run_task(breaks: ["banana"])
      _(run.ok?).must_equal false
      _(run.failure[:error]).must_equal "ArgumentError"
    end

    it "refuses a malformed range, naming it" do
      run = run_task(breaks: [5.0, [6.0]])
      _(run.ok?).must_equal false
      _(run.failure[:cause]).must_match(/AdBreaks\[1\] \[6.0\]: a range is \[start, end\]/)
    end

    it "refuses ranges that overlap" do
      run = run_task(breaks: [[3.0, 6.0], [5.0, 8.0]])
      _(run.ok?).must_equal false
      _(run.failure[:cause]).must_match(/overlap or touch/)
    end

    it "reports failure through the callback rather than raising" do
      run = run_task(preset: "nope")
      _(run.failure[:task_token]).must_equal "task-runner-token"
      _(run.failure[:error]).must_equal "StandardError"
    end
  end

  describe "a complete task" do
    # One real encode, shared by the assertions below.
    def self.completed
      @completed ||= TaskRunner.run(source: source, upload_to: out_dir(:complete),
        task: {"Type" => "HLS", "Preset" => preset_name, "AdBreaks" => [7.5]})
    end

    it "succeeds and reports every rendition it produced" do
      run = self.class.completed
      _(run.failure).must_be_nil
      _(run.ok?).must_equal true

      labels = run.task_result["Assets"]["Variants"].map { |v| v["PresetLabel"] }
      # 1080p and 720p are skipped rather than upscaled from a 480p source
      _(labels).must_equal %w[480P AUDIO IFRAME]
    end

    it "uploads each rendition's media and playlist, plus both masters" do
      keys = self.class.completed.uploaded.map { |u| u[:key] }.sort
      _(keys).must_equal %w[
        480p.m3u8 480p.ts audio.m3u8 audio.ts iframe.m3u8 iframe.ts
        index-compat.m3u8 index.m3u8
      ]
    end

    it "gives playlists the HLS content type" do
      uploaded = self.class.completed.uploaded
      m3u8 = uploaded.select { |u| u[:key].end_with?(".m3u8") }
      ts = uploaded.select { |u| u[:key].end_with?(".ts") }
      _(m3u8.map { |u| u[:content_type] }.uniq).must_equal ["application/vnd.apple.mpegurl"]
      _(ts.map { |u| u[:content_type] }.uniq).must_equal ["video/mp2t"]
    end

    it "reports where the break actually landed" do
      breaks = self.class.completed.task_result["AdBreaks"]
      _(breaks.length).must_equal 1
      _(breaks.first["RequestedTime"]).must_equal 7.5
      _(breaks.first["ActualTime"]).must_equal 7.5
      # zero-based, so the ad goes after the segment ending at 7.5s
      _(breaks.first["InsertAfterSegmentIndex"]).must_equal 1
    end

    it "marks the break in the delivery playlists, but not trickplay" do
      self.class.completed
      counts = %w[480p.m3u8 audio.m3u8 iframe.m3u8].map do |name|
        text = File.read(File.join(self.class.out_dir(:complete), name))
        text.scan("#EXT-X-CUE-OUT").length
      end
      _(counts).must_equal [1, 1, 0]
    end

    it "puts a CUE-OUT/CUE-IN pair after the segment that ends at the break" do
      # Adjacent: a splice point, not a span.
      self.class.completed
      lines = File.readlines(File.join(self.class.out_dir(:complete), "480p.m3u8")).map(&:chomp)
      at = lines.index("#EXT-X-CUE-OUT")
      _(lines[at - 1]).must_equal "480p.ts"
      _(lines[at + 1]).must_equal "#EXT-X-CUE-IN"
      _(lines[at + 2]).must_match(/\A#EXTINF:/)
    end

    it "reports the program date time the interstitial START-DATEs resolve against" do
      pdt = self.class.completed.task_result["ProgramDateTime"]
      _(pdt).must_match(/\A\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}\.\d{3}Z\z/)
    end

    it "omits AdBreaks entirely when none were requested" do
      run = run_task(breaks: [])
      _(run.ok?).must_equal true
      _(run.task_result.key?("AdBreaks")).must_equal false
    end

    it "adds no cut fields when nothing was cut" do
      result = self.class.completed.task_result
      _(result.key?("Duration")).must_equal false
      _(result.key?("Trims")).must_equal false
    end
  end

  describe "cutting AdBreaks ranges" do
    # Two real encodes of the 13s sample, shared by the assertions below.
    # 4-6 removed with a break there, and a point at 9 that lands at 7.
    def self.cut
      @cut ||= TaskRunner.run(source: source, upload_to: out_dir(:cut),
        task: {"Type" => "HLS", "Preset" => preset_name, "AdBreaks" => [[4.0, 6.0], 9.0]})
    end

    # The first 2s and everything from 11s trimmed, plus a point at 6 that lands at 4.
    def self.trimmed
      @trimmed ||= TaskRunner.run(source: source, upload_to: out_dir(:trimmed),
        task: {"Type" => "HLS", "Preset" => preset_name, "AdBreaks" => [[0, 2.0], [11.0, nil], 6.0]})
    end

    def total(name, playlist)
      Hls::MediaPlaylist.segments(File.join(self.class.out_dir(name), playlist)).sum(&:duration)
    end

    it "removes the range and reports both breaks in the edited timeline" do
      run = self.class.cut
      _(run.failure).must_be_nil
      _(run.task_result["AdBreaks"]).must_equal [
        {"RequestedTime" => [4.0, 6.0], "ActualTime" => 4.0, "InsertAfterSegmentIndex" => 0, "RemovedDuration" => 2.0},
        {"RequestedTime" => 9.0, "ActualTime" => 7.0, "InsertAfterSegmentIndex" => 1}
      ]
    end

    it "shortens every rendition by what was removed" do
      self.class.cut
      _(total(:cut, "480p.m3u8")).must_be_close_to 11.0, 0.001
      _(total(:cut, "iframe.m3u8")).must_be_close_to 11.0, 0.5
      # audio may run over by an AAC frame
      _(total(:cut, "audio.m3u8")).must_be_close_to 11.0, 1024.0 / 48000 * 2
      _(self.class.cut.task_result["Duration"]).must_be_close_to 11.0, 0.001
    end

    it "marks both breaks in the delivery playlists, but not trickplay" do
      self.class.cut
      counts = %w[480p.m3u8 audio.m3u8 iframe.m3u8].map do |name|
        File.read(File.join(self.class.out_dir(:cut), name)).scan("#EXT-X-CUE-OUT").length
      end
      _(counts).must_equal [2, 2, 0]
    end

    it "trims the start and end without placing breaks there" do
      run = self.class.trimmed
      _(run.failure).must_be_nil
      _(run.task_result["AdBreaks"]).must_equal [
        {"RequestedTime" => 6.0, "ActualTime" => 4.0, "InsertAfterSegmentIndex" => 0}
      ]
      _(run.task_result["Trims"]).must_equal [
        {"RequestedTime" => [0.0, 2.0], "RemovedDuration" => 2.0},
        {"RequestedTime" => [11.0, nil], "RemovedDuration" => 2.0}
      ]
      _(run.task_result["Duration"]).must_be_close_to 9.0, 0.001
      _(total(:trimmed, "480p.m3u8")).must_be_close_to 9.0, 0.001
    end

    it "says when a time is in the edited timeline" do
      # 3.5 lands at 0.5 once 0-3 is gone, too early for the muxer's first split
      run = run_task(breaks: [[0, 3.0], 3.5])
      _(run.ok?).must_equal false
      _(run.failure[:cause]).must_match(/not reachable/)
      _(run.failure[:cause]).must_match(/edited timeline, after removing 3.0s/)
    end
  end

  describe "when ffmpeg fails" do
    # Stubs the encode: real output from a shell that writes both streams.
    def with_failing_ffmpeg
      failed = Open3.capture3("sh", "-c", "echo to-stdout; echo a-warning >&2; echo the-error >&2; exit 3")
      original = Open3.method(:capture3)
      # Only the encode: ffprobe and the encoder's availability probe run for real.
      Open3.define_singleton_method(:capture3) do |*args, **opts|
        encode = args.first == "ffmpeg" && args.include?("artifact.file")
        encode ? failed : original.call(*args, **opts)
      end
      yield
    ensure
      Open3.define_singleton_method(:capture3, original)
    end

    it "logs stdout and stderr in full" do
      run = with_failing_ffmpeg { run_task }
      out = logged(run, "FFmpeg output")
      _(out["exit_status"]).must_equal 3
      _(out["stdout"]).must_equal "to-stdout\n"
      _(out["stderr"]).must_equal "a-warning\nthe-error\n"
    end

    it "reports the tail of stderr through the callback" do
      run = with_failing_ffmpeg { run_task }
      _(run.failure[:cause]).must_equal "FFmpeg failed (exit 3): a-warning\nthe-error"
    end

    it "logs no ffmpeg output for a failure before the encode" do
      _(logged(run_task(preset: "nope"), "FFmpeg output")).must_be_nil
    end
  end

  describe "source requirements" do
    it "fails on an unreadable source with ffprobe's own error, logged in full" do
      Dir.mktmpdir do |dir|
        junk = File.join(dir, "junk.mp4")
        File.write(junk, "not a video")
        run = run_task(source: junk)
        _(run.failure[:cause]).must_match(/\AFFprobe failed \(exit \d+\): .*Invalid data found/m)
        _(logged(run, "FFprobe output")["stderr"]).must_include "Invalid data found"
      end
    end

    it "fails when no rung is at or below the source height" do
      run = run_task(source: File.expand_path("samples/tiny-video.ts", __dir__))
      _(run.ok?).must_equal false
      _(run.failure[:cause]).must_match(/No rungs at or below the source height/)
    end

    it "fails when the encoder adds keyframes of its own" do
      # A keyframe a second on top of the forced list: every rung gains the same extra
      # segments, so only audio differs. Prepended to outlive hls.rb reloading the class;
      # the flag confines it to this test.
      require_relative "../lib/encoders"
      extra_keyframes = true
      Hls::Encoders::X264.prepend(Module.new do
        define_method(:keyframe_options) { (extra_keyframes ? [["g", "30"]] : []) + super() }
      end)
      run = run_task(breaks: [7.5])
      _(run.ok?).must_equal false
      _(run.failure[:cause]).must_match(/audio has \d+ segments but video has \d+/)
    ensure
      extra_keyframes = false
    end

    it "fails on a source with no audio stream" do
      run = run_task(source: File.expand_path("samples/source-480p-video-only.mp4", __dir__))
      _(run.ok?).must_equal false
      _(run.failure[:cause]).must_equal "Artifact has no audio stream"
    end

    it "fails on a source with no video stream" do
      run = run_task(source: File.expand_path("samples/source-audio-only.m4a", __dir__))
      _(run.ok?).must_equal false
      _(run.failure[:cause]).must_match(/no video stream/i)
    end
  end
end
