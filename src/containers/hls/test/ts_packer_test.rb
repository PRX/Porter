# frozen_string_literal: true

# Combine MPEG-TS packets, no ffmpeg. Run: make test
require "minitest/autorun"
require "tmpdir"
require_relative "../lib/ts_packer"

describe Hls::TsPacker do
  # Build one 188-byte TS packet.
  #   afc 1 = payload only, 2 = adaptation field only (no payload), 3 = both
  def packet(pid:, cc:, afc: 1)
    bytes = [0x47, (pid >> 8) & 0x1F, pid & 0xFF, ((afc & 0x03) << 4) | (cc & 0x0F)]
    (bytes + Array.new(Hls::TsPacker::TS_PACKET - 4, 0xFF)).pack("C*")
  end

  # A part as the segment muxer writes it: PAT, PMT, then payload -- every part
  # restarting its counters at 0, which is the whole problem.
  def part(payload_packets: 3)
    [packet(pid: 0x0000, cc: 0), packet(pid: 0x1000, cc: 0)].join +
      Array.new(payload_packets) { |i| packet(pid: 0x0100, cc: i) }.join
  end

  def counters_of(data, pid)
    out = []
    (data.bytesize / Hls::TsPacker::TS_PACKET).times do |i|
      off = i * Hls::TsPacker::TS_PACKET
      p = ((data.getbyte(off + 1) & 0x1F) << 8) | data.getbyte(off + 2)
      out << (data.getbyte(off + 3) & 0x0F) if p == pid
    end
    out
  end

  def packer
    Hls::TsPacker.new(parts_playlist: "/dev/null", out_media: "/dev/null",
      out_playlist: "/dev/null", version: 7)
  end

  describe "#renumber_continuity" do
    it "makes counters continuous across independently muxed parts" do
      counters = {}
      a, = packer.renumber_continuity(part, counters)
      b, = packer.renumber_continuity(part, counters)

      # Each part restarted at 0; after renumbering the elementary stream runs 0..5
      _(counters_of(a, 0x0100) + counters_of(b, 0x0100)).must_equal [0, 1, 2, 3, 4, 5]
      # ...and so do the table PIDs, which players like VLC also check
      _(counters_of(a, 0x0000) + counters_of(b, 0x0000)).must_equal [0, 1]
      _(counters_of(a, 0x1000) + counters_of(b, 0x1000)).must_equal [0, 1]
    end

    it "wraps the 4-bit counter" do
      counters = {}
      joined = 20.times.map { packer.renumber_continuity(part(payload_packets: 1), counters).first }.join
      # 20 payload packets on one PID -> 0..15 then 0..3
      _(counters_of(joined, 0x0100)).must_equal (0..15).to_a + [0, 1, 2, 3]
    end

    it "leaves null packets untouched" do
      counters = {}
      data = packet(pid: 0x1FFF, cc: 9) + packet(pid: 0x0100, cc: 7)
      out, = packer.renumber_continuity(data, counters)
      _(counters_of(out, 0x1FFF)).must_equal [9]      # unchanged
      _(counters_of(out, 0x0100)).must_equal [0]      # renumbered
      _(counters).wont_include 0x1FFF
    end

    it "does not increment on adaptation-only packets" do
      # Per ISO 13818-1 the counter advances only on packets carrying a payload.
      counters = {}
      data = packet(pid: 0x0100, cc: 0, afc: 1) +
        packet(pid: 0x0100, cc: 0, afc: 2) +
        packet(pid: 0x0100, cc: 0, afc: 1)
      out, = packer.renumber_continuity(data, counters)
      _(counters_of(out, 0x0100)).must_equal [0, 0, 1]
    end

    it "reports misalignment rather than corrupting the data" do
      # The garbage has to fill a whole packet slot: the walk steps 188 bytes at a
      # time, so a shorter tail is simply never examined.
      counters = {}
      data = part + ("X" * Hls::TsPacker::TS_PACKET) + part
      out, aligned = packer.renumber_continuity(data, counters)
      _(aligned).must_equal false
      _(out.bytesize).must_equal data.bytesize
      # everything before the bad packet is still renumbered
      _(counters_of(out[0, part.bytesize], 0x0100)).must_equal [0, 1, 2]
    end

    it "reports a part whose size is not a whole number of packets" do
      counters = {}
      _, aligned = packer.renumber_continuity(part + "tail", counters)
      _(aligned).must_equal false
    end

    it "is a no-op on already-continuous input" do
      counters = {}
      good = Array.new(4) { |i| packet(pid: 0x0100, cc: i) }.join
      out, = packer.renumber_continuity(good, counters)
      _(out).must_equal good
    end
  end

  describe ".count_discontinuities" do
    it "counts the joins in naively concatenated parts" do
      Dir.mktmpdir do |dir|
        path = File.join(dir, "naive.ts")
        File.binwrite(path, part + part + part)
        # 3 parts, 2 joins, 3 PIDs each restarting => 6
        _(Hls::TsPacker.count_discontinuities(path)).must_equal 6
      end
    end

    it "counts zero once renumbered" do
      Dir.mktmpdir do |dir|
        counters = {}
        p = packer
        data = 3.times.map { p.renumber_continuity(part, counters).first }.join
        path = File.join(dir, "fixed.ts")
        File.binwrite(path, data)
        _(Hls::TsPacker.count_discontinuities(path)).must_equal 0
      end
    end
  end

  describe "#pack" do
    it "concatenates parts and emits a byterange playlist with zero discontinuities" do
      Dir.mktmpdir do |dir|
        3.times { |i| File.binwrite(File.join(dir, format("a%05d.ts", i)), part) }
        parts_pl = File.join(dir, "parts.m3u8")
        File.write(parts_pl, (0..2).flat_map { |i|
          ["#EXTINF:6.000000,", format("a%05d.ts", i)]
        }.join("\n"))

        media = File.join(dir, "audio.ts")
        playlist = File.join(dir, "audio.m3u8")
        count = Hls::TsPacker.new(parts_playlist: parts_pl, out_media: media,
          out_playlist: playlist, version: 7).pack

        _(count).must_equal 3
        _(Hls::TsPacker.count_discontinuities(media)).must_equal 0

        text = File.read(playlist)
        _(text).must_include "#EXT-X-VERSION:7"
        _(text).must_include "#EXT-X-PLAYLIST-TYPE:VOD"
        _(text).must_include "#EXT-X-TARGETDURATION:6"
        _(text).must_include "#EXT-X-ENDLIST"
        # declared in the master only, never here
        _(text).wont_include "#EXT-X-INDEPENDENT-SEGMENTS"

        # byteranges must be contiguous and cover the file exactly
        ranges = text.scan(/#EXT-X-BYTERANGE:(\d+)@(\d+)/).map { |l, o| [l.to_i, o.to_i] }
        _(ranges.length).must_equal 3
        expected_offset = 0
        ranges.each do |len, off|
          _(off).must_equal expected_offset
          expected_offset += len
        end
        _(expected_offset).must_equal File.size(media)
      end
    end

    it "raises when the parts playlist has no segments" do
      Dir.mktmpdir do |dir|
        parts_pl = File.join(dir, "empty.m3u8")
        File.write(parts_pl, "#EXTM3U\n")
        p = Hls::TsPacker.new(parts_playlist: parts_pl,
          out_media: File.join(dir, "o.ts"),
          out_playlist: File.join(dir, "o.m3u8"), version: 7)
        _ { p.pack }.must_raise RuntimeError
      end
    end
  end
end
