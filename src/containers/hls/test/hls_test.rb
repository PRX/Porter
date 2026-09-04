# frozen_string_literal: true

require "minitest/autorun"
require "json"
require_relative "harness/task_runner"

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

    it "reports failure through the callback rather than raising" do
      run = run_task(preset: "nope")
      _(run.failure[:task_token]).must_equal "task-runner-token"
      _(run.failure[:error]).must_equal "StandardError"
    end
  end

  describe "a complete task" do
    # One real encode, shared by the assertions below.
    def self.completed
      @completed ||= TaskRunner.run(source: source,
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

    it "reports the program date time the interstitial START-DATEs resolve against" do
      pdt = self.class.completed.task_result["ProgramDateTime"]
      _(pdt).must_match(/\A\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}\.\d{3}Z\z/)
    end

    it "omits AdBreaks entirely when none were requested" do
      run = run_task(breaks: [])
      _(run.ok?).must_equal true
      _(run.task_result.key?("AdBreaks")).must_equal false
    end
  end

  describe "source requirements" do
    it "fails when no rung is at or below the source height" do
      run = run_task(source: File.expand_path("samples/tiny-video.ts", __dir__))
      _(run.ok?).must_equal false
      _(run.failure[:cause]).must_match(/No rungs at or below the source height/)
    end

    it "fails on a source with no video stream" do
      run = run_task(source: File.expand_path("samples/source-audio-only.m4a", __dir__))
      _(run.ok?).must_equal false
      _(run.failure[:cause]).must_match(/no video stream/i)
    end
  end
end
