# frozen_string_literal: true

# Pure computation: no AWS, no ffmpeg, no fixtures. Run: make test
require "minitest/autorun"
require "json"
require_relative "../lib/boundaries"

describe Hls::Boundaries do
  # Defaults matching the preset, so each test only states what it varies.
  def build(breaks: [], duration: 300.216583, target: 6, fps: "30", hls_time: 2,
    max_seg: nil, audio_grain: nil)
    Hls::Boundaries.build(duration: duration, target: target, fps: fps,
      hls_time: hls_time, breaks: breaks, max_seg: max_seg, audio_grain: audio_grain)
  end

  def gaps(list, duration)
    edges = [0.0] + list.map(&:to_f) + [duration]
    edges.each_cons(2).map { |a, b| (b - a).round(4) }
  end

  describe "the plain grid" do
    it "emits the regular cadence when there are no breaks" do
      layout = build
      _(layout.segments.first(4)).must_equal %w[6.000000 12.000000 18.000000 24.000000]
      _(layout.breaks).must_equal []
    end

    it "never emits a leading zero" do
      # 0 in -segment_times is treated as a real split target and
      # shifts the whole mapping by one - make sure we prevent this
      _(build.segments).wont_include "0.000000"
      _(build(breaks: [90.5]).keyframes).wont_include "0.000000"
    end

    it "leaves no runt segment at the head or tail" do
      g = gaps(build.segments, 300.216583)
      _(g.min).must_be :>=, 2
    end
  end

  describe "break quantization" do
    it "snaps a break to the nearest frame" do
      # 90.47 * 30 = 2714.1 -> frame 2714 -> 90.466667
      _(build(breaks: [90.47]).breaks.map(&:at)).must_equal ["90.466667"]
    end

    it "quantizes against a rational frame rate" do
      # 23.976 fps: 90.5 * 24000/1001 -> frame 2170 -> 90.507083
      layout = build(breaks: [90.5], fps: "24000/1001")
      _(layout.breaks.map(&:at)).must_equal ["90.507083"]
    end

    it "leaves a break already on a frame boundary alone" do
      _(build(breaks: [90.5]).breaks.map(&:at)).must_equal ["90.500000"]
    end

    it "refuses a break outside the asset rather than dropping it" do
      e = _ { build(breaks: [90.5, 1000]) }.must_raise RuntimeError
      _(e.message).must_match(/1000/)
      _(e.message).must_match(/have to be > 0 and before/)
    end

    it "names the snapped time when only the quantized break is out of range" do
      # to distinguish from a request that was out of range to begin with
      e = _ { build(breaks: [299.99], duration: 300.0) }.must_raise RuntimeError
      _(e.message).must_match(/snaps to 300\.000000/)
    end

    it "refuses two breaks that land on the same frame" do
      e = _ { build(breaks: [100.001, 100.002]) }.must_raise RuntimeError
      _(e.message).must_match(/collide after quantization/)
    end
  end

  describe "the half-frame bias on keyframe times" do
    it "biases break keyframe times half a frame early" do
      layout = build(breaks: [90.5])
      _(layout.breaks.map(&:at)).must_include "90.500000"
      _(layout.keyframes).must_include "90.483333"   # 90.5 - 1/60
      _(layout.keyframes).wont_include "90.500000"
    end

    it "does not bias regular grid points" do
      layout = build(breaks: [90.5])
      _(layout.keyframes).must_include "24.000000"
    end

    it "keeps the unbiased time in the segments view for audio" do
      # audio needs no encoder bias -- every audio frame is a keyframe
      _(build(breaks: [90.5]).segments).must_include "90.500000"
    end
  end

  describe "pruning around a break" do
    it "drops a grid point that sits within min_segment of a break" do
      # 90.5 is 0.5s from grid point 90, so 90 must go.
      layout = build(breaks: [90.5])
      _(layout.segments).wont_include "90.000000"
      _(layout.segments).must_include "90.500000"
    end

    it "keeps a grid point far enough from a break" do
      layout = build(breaks: [90.5])
      _(layout.segments).must_include "96.000000"
    end

    it "treats a break landing exactly on the grid as one boundary" do
      # 1200 is a multiple of the 6s target. Break and grid point are the same.
      layout = build(breaks: [1200.0], duration: 3251.328)
      _(layout.breaks.map(&:at)).must_equal ["1200.000000"]

      segs = layout.segments
      _(segs).must_include "1200.000000"
      _(segs.count { |s| s.to_f > 1200 && s.to_f < 1206 }).must_equal 0

      g = gaps(segs, 3251.328)
      _(g.select { |x| x < 4 }).must_equal []
    end

    it "keeps two breaks closer together than min_segment" do
      layout = build(breaks: [90.5, 91.0])
      _(layout.breaks.map(&:at)).must_equal %w[90.500000 91.000000]
      _(layout.breaks.map(&:at) - layout.segments).must_equal []
    end

    it "keeps both when they are at least min_segment apart" do
      layout = build(breaks: [90.5, 93.0])
      _(layout.breaks.map(&:at)).must_equal %w[90.500000 93.000000]
      _(layout.breaks.map(&:at) - layout.segments).must_equal []
    end
  end

  describe "the maximum segment cap" do
    it "biases audio splits half an audio frame early, so each lands on the nearest" do
      # The segment muxer cuts at the first audio frame AT OR AFTER the time given,
      # so the bias turns "next frame" into "nearest frame".
      grain = Rational(1024, 48_000)
      layout = build(breaks: [90.5], audio_grain: grain)
      offsets = layout.segments.zip(layout.audio_splits)
        .map { |s, a| (s.to_f - a.to_f).round(6) }
      _(offsets.uniq).must_equal [(grain / 2).to_f.round(6)]
    end

    it "leaves audio splits equal to the boundaries when no grain is given" do
      # A caller with no audio rendition needs no bias, and the muxer's own rounding
      # is then the only error.
      layout = build(breaks: [90.5])
      _(layout.audio_splits).must_equal layout.segments
    end

    it "leaves no segment over the cap for the regression case" do
      layout = build(breaks: [90.5, 187.3])
      g = gaps(layout.segments, 300.216583)
      _(g.select { |x| x > 6.0001 }).must_equal []
      _(g.max).must_be :<=, 6.0
    end

    it "subdivides rather than moving the break" do
      layout = build(breaks: [187.3])
      _(layout.breaks.map(&:at)).must_equal ["187.300000"]
      # 180 -> 187.3 was 7.3s (grid point 186 was pruned)
      # expect an inserted boundary between them!
      inserted = layout.segments.map(&:to_f).select { |t| t > 180 && t < 187.3 }
      _(inserted).wont_be_empty
    end

    it "honors an explicit max_seg tighter than target" do
      g = gaps(build(max_seg: 4).segments, 300.216583)
      _(g.select { |x| x > 4.0001 }).must_equal []
    end

    it "keeps every segment at or above min_segment while capping" do
      g = gaps(build(breaks: [90.5, 187.3]).segments, 300.216583)
      _(g.min).must_be :>=, 2
    end
  end

  describe "the reported breaks" do
    it "pairs each request with the frame it was snapped to" do
      # the pairing must follow the frame times, not the order they arrived in.
      layout = build(breaks: [93.0, 90.47])
      _(layout.breaks.map(&:requested)).must_equal [90.47, 93.0]
      _(layout.breaks.map(&:at)).must_equal ["90.466667", "93.000000"]
    end
  end

  describe "muxer reachability" do
    # The hls muxer's split threshold is cumulative, so the k-th boundary cannot
    # precede k * hls_time (more in the README about this).
    # Make sure we expect this and plan breaks accordingly
    it "refuses a break the muxer would skip" do
      # 1.0 is the first boundary and 1.0 < hls_time, so the muxer keeps its
      # keyframe but never splits there.
      e = _ { build(breaks: [1.0], duration: 60.0, hls_time: 2) }.must_raise RuntimeError
      _(e.message).must_match(/1\.000000/)
      _(e.message).must_match(/not reachable/)
    end

    it "refuses hls_time longer than the target before laying out a grid" do
      e = _ { build(breaks: [], duration: 300.0, target: 4, hls_time: 6, max_seg: 4) }
        .must_raise RuntimeError
      _(e.message).must_match(/hls_time \(6\.0s\) is longer than the segment target/)
      _(e.message).wont_match(/not reachable/)
    end

    it "allows the same break once hls_time is low enough" do
      # Nothing about the break is wrong -- it is unreachable only relative to
      # hls_time, which the message says to lower.
      layout = build(breaks: [1.0], duration: 60.0, hls_time: 1)
      _(layout.segments).must_include "1.000000"
    end

    it "allows a break near the end, where EOF flushes regardless" do
      # The tail is not symmetric with the head: the final segment is whatever is
      # left, so a short one there is fine and the break still lands.
      layout = build(breaks: [59.0], duration: 60.0, hls_time: 2)
      _(layout.segments).must_include "59.000000"
    end

    it "allows a tiny segment mid-stream, where the target has fallen behind" do
      # Boundaries 0.1s apart are reachable once cumulative slack has built up.
      # min_segment is what normally prevents them, not the muxer.
      layout = Hls::Boundaries.build(duration: 60.0, target: 6, fps: "30",
        hls_time: 2, min_segment: Rational(1, 100), breaks: [12.1])
      _(layout.segments).must_include "12.100000"
      _(gaps(layout.segments, 60.0).min).must_be :<, 1
    end

    it "reports every unreachable boundary, not just the first" do
      # Needs min_segment below hls_time to produce more than one. With the
      # default they are equal, every gap is >= hls_time, so boundary k is always
      # >= k * hls_time and only an exempted break at the very head can fail --
      # which is why the default couples them.
      e = _ {
        Hls::Boundaries.build(duration: 60.0, target: 6, fps: "30",
          hls_time: 5, min_segment: 1, breaks: [1.0, 2.0])
      }.must_raise RuntimeError
      _(e.message).must_match(/1\.000000/)
      _(e.message).must_match(/2\.000000/)
    end
  end

  describe "min_segment versus max_seg conflict" do
    it "prefers min_segment and warns when both cannot hold" do
      # Going under min_segment starts authoring segments too short to be useful;
      # one slightly over max_seg only breaches guidance.
      out, err = capture_io do
        layout = Hls::Boundaries.build(duration: 20, target: 10, fps: "30",
          hls_time: 8, breaks: [], max_seg: 9)
        _(gaps(layout.segments, 20).min).must_be :>=, 8
      end
      # Parsing the JSON asserts the shape a log query depends on, which a
      # substring match on prose would not.
      _(err).must_be_empty
      # Both halves breach the cap, so this also pins down that every offending
      # segment is reported, not just the first.
      logged = out.lines.map { |l| JSON.parse(l) }
      _(logged.length).must_equal 2
      _(logged.map { |l| l["from"] }).must_equal ["0.000000", "10.000000"]
      logged.each do |line|
        _(line["msg"]).must_match(/over the max_seg cap/)
        _(line["max_seg"]).must_equal 9.0
        _(line["min_segment"]).must_equal 8.0
      end
    end
  end

  describe ".from_part_durations" do
    it "turns part durations into break times, dropping the final join" do
      result = Hls::Boundaries.from_part_durations([
        {duration: 30.5, fps: "30"},
        {duration: 53.8, fps: "30"},
        {duration: 25.7, fps: "30"}
      ])
      _(result[:breaks]).must_equal %w[30.500000 84.300000]
      _(result[:total]).must_equal "110.000000"
    end

    it "quantizes each part against its own frame rate" do
      result = Hls::Boundaries.from_part_durations([
        {duration: 10.0, fps: "24000/1001"},
        {duration: 10.0, fps: "30"}
      ])
      # 10s at 23.976 is 240 frames -> 10.010000, not 10.0
      _(result[:breaks]).must_equal ["10.010000"]
    end
  end
end
