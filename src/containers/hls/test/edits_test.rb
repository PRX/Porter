# frozen_string_literal: true

# Pure arithmetic, no ffmpeg. Run: make test
require "minitest/autorun"
require_relative "../lib/edits"
require_relative "../lib/boundaries"

describe Hls::Edits do
  def plan(raw, duration: 120.0, fps: "30")
    Hls::Edits.build(Hls::Edits.parse(raw), duration: duration, fps: fps)
  end

  def secs(values) = values.map { |v| v&.to_f&.round(6) }

  def keep(p) = p.keep.map { |span| secs(span) }

  def times(p) = p.breaks.map { |b| b.boundary_time.to_f.round(6) }

  def refusal(raw, **opts)
    _ { plan(raw, **opts) }.must_raise(StandardError).message
  end

  describe ".parse" do
    it "takes numbers, numeric strings, pairs and open-ended pairs" do
      entries = Hls::Edits.parse([[nil, 5], 30, "45.5", [60, 65], [100, nil]])
      _(entries[0].requested).must_equal [nil, 5.0]
      _(entries[0].start).must_equal 0.0
      _(entries[1..2]).must_equal [30.0, 45.5]
      _(entries[3].requested).must_equal [60.0, 65.0]
      _(entries[4].requested).must_equal [100.0, nil]
    end

    it "keeps today's errors for points" do
      _(_ { Hls::Edits.parse([-1.0]) }.must_raise(StandardError).message)
        .must_equal "AdBreaks must be positive numbers of seconds"
      _ { Hls::Edits.parse(["banana"]) }.must_raise ArgumentError
    end

    it "refuses malformed ranges, naming the entry" do
      _(_ { Hls::Edits.parse([10, [1]]) }.must_raise(StandardError).message).must_match(/AdBreaks\[1\] \[1\]/)
      _(_ { Hls::Edits.parse([[1, 2, 3]]) }.must_raise(StandardError).message).must_match(/a range is \[start, end\]/)
      _(_ { Hls::Edits.parse([["x", 2]]) }.must_raise(StandardError).message).must_match(/numbers of seconds/)
      _(_ { Hls::Edits.parse([[1, Float::INFINITY]]) }.must_raise(StandardError).message).must_match(/numbers of seconds/)
      _(_ { Hls::Edits.parse([[-1, 3]]) }.must_raise(StandardError).message).must_match(/can't be negative/)
      _(_ { Hls::Edits.parse([[5, 5]]) }.must_raise(StandardError).message).must_match(/end must be after start/)
    end
  end

  describe "without ranges" do
    it "passes points and duration through untouched, so Boundaries sees today's input" do
      p = plan([30.0, 90.5])
      _(p.cut?).must_equal false
      _(p.keep).must_be_nil
      _(p.duration).must_equal 120.0
      _(p.breaks.map(&:boundary_time)).must_equal [30.0, 90.5]
      _(p.trims).must_equal []
    end
  end

  describe "with ranges" do
    it "removes a range and breaks where it was" do
      p = plan([[60, 65]])
      _(keep(p)).must_equal [[0.0, 60.0], [65.0, nil]]
      _(p.duration).must_equal 115
      _(times(p)).must_equal [60.0]
      _(p.breaks.first.removed).must_equal 5
      _(p.breaks.first.requested).must_equal [60.0, 65.0]
    end

    it "shifts later points earlier by everything removed before them" do
      _(times(plan([30, [60, 65], 120.5], duration: 200.0))).must_equal [30.0, 60.0, 115.5]
    end

    it "quantizes range edges to frames" do
      p = plan([[10.01, 12.52]])
      _(keep(p)).must_equal [[0.0, 10.0], [12.533333, nil]]
      _(p.breaks.first.removed).must_equal Rational(76, 30)
    end

    it "accepts ranges and points in any order" do
      _(times(plan([[90, 95], 30, [60, 65]], duration: 200.0))).must_equal [30.0, 60.0, 85.0]
    end

    it "trims at the start without placing a break" do
      p = plan([[0, 3], 10.0])
      _(keep(p)).must_equal [[3.0, nil]]
      _(times(p)).must_equal [7.0]
      _(p.trims.map(&:position)).must_equal [:head]
      _(p.trims.first.removed).must_equal 3
    end

    it "trims at the start for a null start, as for 0" do
      p = plan([[nil, 3], 10.0])
      _(keep(p)).must_equal [[3.0, nil]]
      _(p.trims.map(&:requested)).must_equal [[nil, 3.0]]
    end

    it "treats a start within half a frame of 0 as a head trim" do
      _(plan([[0.01, 3]]).trims.map(&:position)).must_equal [:head]
    end

    it "trims at the end for a null end, one past the end, or one within the last frame" do
      [[250, nil], [250, 400], [250, 299.99]].each do |range|
        p = plan([range], duration: 300.0)
        _(p.trims.map(&:position)).must_equal [:tail]
        _(keep(p)).must_equal [[0.0, 250.0]]
        _(p.duration).must_equal 250
      end
    end

    it "handles a head trim, a cut and a tail trim together" do
      p = plan([[0, 2.0], [11.0, nil], 6.0], duration: 13.0)
      _(keep(p)).must_equal [[2.0, 11.0]]
      _(p.duration).must_equal 9
      _(times(p)).must_equal [4.0]
      _(p.trims.map(&:position)).must_equal [:head, :tail]
      _(p.removed).must_equal 4
    end

    it "refuses overlapping or touching ranges" do
      _(refusal([[10, 20], [15, 30]])).must_match(/overlap or touch/)
      _(refusal([[10, 20], [20, 30]])).must_match(/overlap or touch/)
    end

    it "refuses a range shorter than a frame once rounded" do
      _(refusal([[10.0, 10.01]])).must_match(/shorter than one frame/)
    end

    it "refuses a range starting at or after the end" do
      _(refusal([[130, 140]])).must_match(/starts at or after the end/)
    end

    it "refuses a range that would remove everything" do
      _(refusal([[0, nil]])).must_match(/whole source/)
    end

    it "refuses a point inside a range or on its edge" do
      _(refusal([15, [10, 20]])).must_match(/break 15.0 falls inside/)
      _(refusal([20, [10, 20]])).must_match(/on the edge/)
      _(refusal([10, [10, 20]])).must_match(/on the edge/)
    end

    it "refuses a point at or after the end" do
      _(refusal([[10, 20], 125])).must_match(/at or after the end/)
    end

    it "refuses two points on the same frame" do
      _(refusal([[10, 20], 30.01, 30.012])).must_match(/same frame/)
    end
  end

  describe "with Boundaries" do
    it "lands every break exactly where the edit put it" do
      p = plan([30, [60, 65], [100.01, 102.52], 150.5], duration: 200.0)
      layout = Hls::Boundaries.build(duration: p.duration, target: 6, fps: "30", hls_time: 1,
        breaks: p.breaks.map(&:boundary_time), min_segment: 2)
      _(layout.breaks.map(&:at)).must_equal %w[30.000000 60.000000 95.000000 142.966667]
    end

    it "joins placed breaks back to what was asked for" do
      p = plan([[60, 65], 30])
      layout = Hls::Boundaries.build(duration: p.duration, target: 6, fps: "30", hls_time: 1,
        breaks: p.breaks.map(&:boundary_time))
      placed = Hls::Edits.placed(p, layout)
      _(placed.map(&:requested)).must_equal [30.0, [60.0, 65.0]]
      _(placed.map(&:at)).must_equal %w[30.000000 60.000000]
      _(placed.map(&:removed)).must_equal [nil, 5]
    end
  end
end
