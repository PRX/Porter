# frozen_string_literal: true

# Fixture playlists only. Run: make test
require "minitest/autorun"
require "tmpdir"
require_relative "../lib/break_report"
require_relative "../lib/boundaries"

# Half a frame at 30fps, the tolerance the task passes in production. Hoisted out
# of the describe block: a constant defined in a block lands at top level anyway.
BREAK_REPORT_TOLERANCE = 1.0 / 60

describe Hls::BreakReport do
  # Write a media playlist whose segment boundaries are exactly `times`.
  def playlist_with_boundaries(dir, times, name: "720p.m3u8")
    path = File.join(dir, name)
    previous = 0.0
    body = times.flat_map do |t|
      line = [format("#EXTINF:%.6f,", t - previous), "#EXT-X-BYTERANGE:1000@0", "720p.ts"]
      previous = t
      line
    end
    File.write(path, (["#EXTM3U", "#EXT-X-VERSION:7"] + body + ["#EXT-X-ENDLIST", ""]).join("\n"))
    path
  end

  # Takes the same shape Boundaries hands over: requested time paired with the
  # frame it snapped to.
  def report(requested, intended, playlist)
    breaks = Array(requested).zip(Array(intended)).map { |r, a|
      Hls::Boundaries::Break.new(requested: r, at: a)
    }
    Hls::BreakReport.build(breaks, playlist, tolerance: BREAK_REPORT_TOLERANCE)
  end

  describe "with no breaks" do
    it "returns an empty array so the caller can omit the key" do
      Dir.mktmpdir do |dir|
        pl = playlist_with_boundaries(dir, [6.0, 12.0])
        _(report([], [], pl)).must_equal []
        _(report(nil, nil, pl)).must_equal []
      end
    end
  end

  describe "placement" do
    it "reports what the caller asked for, and where it landed" do
      Dir.mktmpdir do |dir|
        pl = playlist_with_boundaries(dir, [6.0, 12.0, 18.0, 24.0, 30.5, 36.5])
        r = report([30.5], [30.5], pl)
        _(r.length).must_equal 1
        _(r.first[:RequestedTime]).must_equal 30.5
        _(r.first[:ActualTime]).must_equal 30.5
      end
    end

    it "reports the request unchanged even when it was snapped to a frame" do
      Dir.mktmpdir do |dir|
        # 30.49 at 30fps snaps to frame 915 = 30.5
        pl = playlist_with_boundaries(dir, [6.0, 12.0, 18.0, 24.0, 30.5, 36.5])
        r = report([30.49], [30.5], pl)
        _(r.first[:RequestedTime]).must_equal 30.49
        _(r.first[:ActualTime]).must_equal 30.5
      end
    end

    it "reports the index of the segment to insert after, zero-based" do
      Dir.mktmpdir do |dir|
        pl = playlist_with_boundaries(dir, [6.0, 12.0, 18.0, 24.0, 30.5, 36.5])
        _(report([30.5], [30.5], pl).first[:InsertAfterSegmentIndex]).must_equal 4
      end
    end

    it "handles several breaks in order" do
      Dir.mktmpdir do |dir|
        pl = playlist_with_boundaries(dir, [6.0, 12.0, 18.0, 24.0, 30.5, 36.5, 42.5, 48.5, 54.5])
        r = report([30.5, 48.5], [30.5, 48.5], pl)
        _(r.map { |b| b[:RequestedTime] }).must_equal [30.5, 48.5]
        _(r.map { |b| b[:ActualTime] }).must_equal [30.5, 48.5]
        _(r.map { |b| b[:InsertAfterSegmentIndex] }).must_equal [4, 7]
      end
    end

    it "raises when the encoder did not honor the keyframe list" do
      Dir.mktmpdir do |dir|
        # Nothing at 30.5, so the nearest boundary is 500ms away, much larger than a frame
        # That is a mis-placed ad, so it fails rather than returning.
        pl = playlist_with_boundaries(dir, [6.0, 12.0, 18.0, 24.0, 30.0, 36.0])
        e = _ { report([30.5], [30.5], pl) }.must_raise RuntimeError
        _(e.message).must_match(/requested at 30\.5s but the nearest is 30\.0s/)
      end
    end

    it "tolerates float noise in the EXTINF sum" do
      Dir.mktmpdir do |dir|
        # Cumulative EXTINF addition drifts well under a millisecond over hundreds
        # of segments; that must not be mistaken for a real miss.
        pl = playlist_with_boundaries(dir, [6.0, 12.0, 18.0, 24.0, 30.5001, 36.5])
        r = report([30.5], [30.5], pl)
        _(r.first[:ActualTime]).must_equal 30.5001
      end
    end

    it "raises when the playlist has no segments" do
      Dir.mktmpdir do |dir|
        pl = File.join(dir, "empty.m3u8")
        File.write(pl, "#EXTM3U\n#EXT-X-VERSION:7\n")
        _ { report([30.0], [30.0], pl) }.must_raise RuntimeError
      end
    end
  end

  describe "shape" do
    it "uses PascalCase keys, matching the surrounding task result" do
      Dir.mktmpdir do |dir|
        pl = playlist_with_boundaries(dir, [6.0, 12.0])
        keys = report([6.0], [6.0], pl).first.keys
        _(keys).must_equal %i[RequestedTime ActualTime InsertAfterSegmentIndex]
      end
    end

    it "survives a round trip through JSON" do
      Dir.mktmpdir do |dir|
        require "json"
        pl = playlist_with_boundaries(dir, [6.0, 12.0, 18.0])
        parsed = JSON.parse(JSON.dump(report([12.0], [12.0], pl)))
        _(parsed.first["RequestedTime"]).must_equal 12.0
        _(parsed.first["ActualTime"]).must_equal 12.0
        _(parsed.first["InsertAfterSegmentIndex"]).must_equal 1
      end
    end
  end
end
