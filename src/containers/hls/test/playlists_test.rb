# frozen_string_literal: true

# Fixture playlists and synthetic TS, no ffmpeg encode. Run: make test
require "minitest/autorun"
require "tmpdir"
require "fileutils"
require_relative "../lib/playlists"

# Stand-in for the preset; only the constants Playlists reads
module PlaylistTestSettings
  MASTER_PLAYLIST = "index.m3u8"
  COMPAT_MASTER_PLAYLIST = "index-compat.m3u8"
  TARGET_DURATION_RANGE = (6..10)
  MULTIVARIANT_VERSION = 4
  MEDIA_PLAYLIST_VERSION = 7
  AUDIO_CODEC = "mp4a.40.2"
  AUDIO_LANGUAGE = "en"
  AUDIO_CHANNELS = "2"
end

describe Hls::Playlists do
  def ts_packet(pid)
    ([0x47, (pid >> 8) & 0x1F, pid & 0xFF, 0x10] + Array.new(Hls::Playlists::TS_PACKET - 4, 0)).pack("C*")
  end

  # PAT + SDT + PMT then payload -- the 3-packet, 564-byte init prefix ffmpeg
  # actually writes, which is the value EXT-X-MAP has to point at.
  def ts_with_init(payload_packets: 4)
    [ts_packet(0x0011), ts_packet(0x0000), ts_packet(0x1000)].join +
      Array.new(payload_packets) { ts_packet(0x0100) }.join
  end

  def media_playlist(dir, name, durations:, version: 4, target: nil, extra: [])
    offset = 0
    body = durations.flat_map do |d|
      len = 1000
      line = ["#EXTINF:#{format("%.6f", d)},", "#EXT-X-BYTERANGE:#{len}@#{offset}",
        name.sub(".m3u8", ".ts")]
      offset += len
      line
    end
    header = ["#EXTM3U", "#EXT-X-VERSION:#{version}",
      "#EXT-X-TARGETDURATION:#{target || durations.max.round}",
      "#EXT-X-MEDIA-SEQUENCE:0", "#EXT-X-PLAYLIST-TYPE:VOD"] + extra
    File.write(File.join(dir, name), (header + body + ["#EXT-X-ENDLIST", ""]).join("\n"))
  end

  # A minimal package: two video rungs, audio, trickplay.
  def build_package(dir, video_durations: [6.0, 6.0], audio_durations: [6.016, 6.0107],
    iframe_durations: [0.5, 0.5], audio_target: nil)
    media_playlist(dir, "720p.m3u8", durations: video_durations)
    media_playlist(dir, "480p.m3u8", durations: video_durations)
    media_playlist(dir, "audio.m3u8", durations: audio_durations, target: audio_target)
    media_playlist(dir, "iframe.m3u8", durations: iframe_durations, target: 0)

    sample = File.expand_path("samples/tiny-video.ts", __dir__)
    %w[720p.ts 480p.ts iframe.ts].each { |f| FileUtils.cp(sample, File.join(dir, f)) }
    # Audio is never probed for video properties, so a synthetic TS is fine here.
    File.binwrite(File.join(dir, "audio.ts"), ts_with_init)
  end

  def pdt = "2026-08-28T05:55:22.556Z"

  def playlists_for(dir)
    Hls::Playlists.new(
      dir: dir,
      video_rungs: [
        Hls::Playlists::Rendition.new(playlist: "720p.m3u8", media: "720p.ts", label: "720P"),
        Hls::Playlists::Rendition.new(playlist: "480p.m3u8", media: "480p.ts", label: "480P")
      ],
      audio: Hls::Playlists::Rendition.new(playlist: "audio.m3u8", media: "audio.ts", label: "AUDIO"),
      iframe: Hls::Playlists::Rendition.new(playlist: "iframe.m3u8", media: "iframe.ts", label: "IFRAME"),
      settings: PlaylistTestSettings,
      program_date_time: pdt
    )
  end

  describe "#measure" do
    it "computes peak and average from byteranges" do
      Dir.mktmpdir do |dir|
        # 2s and 4s segments, 1000 bytes each -> peak 4000 bps, average 2666 bps
        media_playlist(dir, "x.m3u8", durations: [2.0, 4.0], target: 4)
        rate = playlists_for(dir).measure("x.m3u8")
        _(rate[:peak]).must_equal 4000
        _(rate[:average]).must_equal 2666
      end
    end

    it "raises on a playlist with no byteranges" do
      Dir.mktmpdir do |dir|
        File.write(File.join(dir, "x.m3u8"), "#EXTM3U\n#EXT-X-VERSION:4\n")
        _ { playlists_for(dir).measure("x.m3u8") }.must_raise RuntimeError
      end
    end
  end

  describe "TARGETDURATION harmonization" do
    it "lifts every rendition to the strictest requirement" do
      Dir.mktmpdir do |dir|
        # video longest 6.5 -> requires 7 (half-up); audio 6.0107 -> requires 6
        build_package(dir, video_durations: [6.5, 6.0], audio_target: 6)
        playlists_for(dir).write_all
        %w[720p.m3u8 480p.m3u8 audio.m3u8].each do |pl|
          _(File.read(File.join(dir, pl))).must_include "#EXT-X-TARGETDURATION:7"
        end
      end
    end

    it "rounds half-up, not banker's" do
      Dir.mktmpdir do |dir|
        # exactly 6.5 must become 7, not 6
        build_package(dir, video_durations: [6.5])
        playlists_for(dir).write_all
        _(File.read(File.join(dir, "720p.m3u8"))).must_include "#EXT-X-TARGETDURATION:7"
      end
    end

    it "does not drag the trickplay playlist up with the rest" do
      Dir.mktmpdir do |dir|
        build_package(dir, video_durations: [6.5, 6.0])
        playlists_for(dir).write_all
        # half-second segments: its own target is 1, not the ladder's 7
        _(File.read(File.join(dir, "iframe.m3u8"))).must_include "#EXT-X-TARGETDURATION:1"
      end
    end

    it "refuses to write a playlist outside the allowed range" do
      Dir.mktmpdir do |dir|
        build_package(dir, video_durations: [14.0, 6.0])
        err = _ { playlists_for(dir).write_all }.must_raise RuntimeError
        _(err.message).must_match(/outside the allowed range/)
        # and must not leave a master behind
        _(File.exist?(File.join(dir, "index.m3u8"))).must_equal false
      end
    end
  end

  describe "EXT-X-VERSION floor" do
    it "raises media playlists to the floor and reports which" do
      Dir.mktmpdir do |dir|
        build_package(dir)
        result = playlists_for(dir).write_all
        %w[720p.m3u8 480p.m3u8 audio.m3u8 iframe.m3u8].each do |pl|
          _(File.read(File.join(dir, pl))).must_include "#EXT-X-VERSION:7"
        end
        _(result[:versions_lifted].length).must_equal 4
      end
    end

    it "never lowers a version already above the floor" do
      Dir.mktmpdir do |dir|
        build_package(dir)
        media_playlist(dir, "720p.m3u8", durations: [6.0], version: 9)
        playlists_for(dir).write_all
        _(File.read(File.join(dir, "720p.m3u8"))).must_include "#EXT-X-VERSION:9"
      end
    end

    it "keeps the multivariant playlist at its own lower floor" do
      Dir.mktmpdir do |dir|
        build_package(dir)
        playlists_for(dir).write_all
        _(File.read(File.join(dir, "index.m3u8"))).must_include "#EXT-X-VERSION:4"
      end
    end
  end

  describe "program date time" do
    it "stamps one identical anchor into every media playlist, before the first segment" do
      Dir.mktmpdir do |dir|
        build_package(dir)
        result = playlists_for(dir).write_all

        %w[720p.m3u8 480p.m3u8 audio.m3u8 iframe.m3u8].each do |pl|
          text = File.read(File.join(dir, pl))
          _(text).must_include "#EXT-X-PROGRAM-DATE-TIME:#{pdt}"
          # An interstitial START-DATE resolves against the FIRST segment, so the
          # tag has to precede it.
          _(text.index("#EXT-X-PROGRAM-DATE-TIME")).must_be :<, text.index("#EXTINF:")
        end

        # Reported, so the caller can compute START-DATEs without refetching.
        _(result[:program_date_time]).must_equal pdt
      end
    end

    it "does not stamp the masters, which carry no segments" do
      Dir.mktmpdir do |dir|
        build_package(dir)
        playlists_for(dir).write_all
        [PlaylistTestSettings::MASTER_PLAYLIST,
          PlaylistTestSettings::COMPAT_MASTER_PLAYLIST].each do |m|
          _(File.read(File.join(dir, m))).wont_include "#EXT-X-PROGRAM-DATE-TIME"
        end
      end
    end
  end

  describe "trickplay finalization" do
    it "adds I-FRAMES-ONLY and an EXT-X-MAP covering the TS init prefix" do
      Dir.mktmpdir do |dir|
        build_package(dir)
        result = playlists_for(dir).write_all
        text = File.read(File.join(dir, "iframe.m3u8"))
        _(text).must_include "#EXT-X-I-FRAMES-ONLY"
        # 3 packets of 188 = the 564 bytes ffmpeg actually writes
        _(text).must_include %(#EXT-X-MAP:URI="iframe.ts",BYTERANGE="564@0")
        _(result[:iframe][:init_section_bytes]).must_equal 564
      end
    end

    it "floors a zero TARGETDURATION at 1" do
      Dir.mktmpdir do |dir|
        # ffmpeg writes 0 for half-second segments, which is not a usable duration
        build_package(dir)
        _(File.read(File.join(dir, "iframe.m3u8"))).must_include "#EXT-X-TARGETDURATION:0"
        playlists_for(dir).write_all
        _(File.read(File.join(dir, "iframe.m3u8"))).wont_include "#EXT-X-TARGETDURATION:0"
        _(File.read(File.join(dir, "iframe.m3u8"))).must_include "#EXT-X-TARGETDURATION:1"
      end
    end

    it "is idempotent for the program date time too" do
      Dir.mktmpdir do |dir|
        build_package(dir)
        playlists_for(dir).write_all
        playlists_for(dir).write_all
        %w[720p.m3u8 480p.m3u8 audio.m3u8 iframe.m3u8].each do |pl|
          _(File.read(File.join(dir, pl)).scan("#EXT-X-PROGRAM-DATE-TIME").length).must_equal 1
        end
      end
    end

    it "is idempotent" do
      Dir.mktmpdir do |dir|
        build_package(dir)
        playlists_for(dir).write_all
        playlists_for(dir).write_all
        text = File.read(File.join(dir, "iframe.m3u8"))
        _(text.scan("#EXT-X-I-FRAMES-ONLY").length).must_equal 1
        _(text.scan("#EXT-X-MAP").length).must_equal 1
      end
    end

    it "raises when the trickplay media has no PAT/PMT to point at" do
      Dir.mktmpdir do |dir|
        build_package(dir)
        # elementary-stream packets only, no program tables
        File.binwrite(File.join(dir, "iframe.ts"), ts_packet(0x0100) * 4)
        _ { playlists_for(dir).write_all }.must_raise RuntimeError
      end
    end
  end

  describe "the two master playlists" do
    it "differ by exactly the audio-only variant" do
      Dir.mktmpdir do |dir|
        build_package(dir)
        playlists_for(dir).write_all
        std = File.read(File.join(dir, "index.m3u8")).lines
        compat = File.read(File.join(dir, "index-compat.m3u8")).lines
        _(std.length - compat.length).must_equal 2
        extra = std - compat
        _(extra.length).must_equal 2
        _(extra.first).must_include %(CODECS="mp4a.40.2")
        _(extra.last.strip).must_equal "audio.m3u8"
      end
    end

    it "adds the audio rate to every video variant's declared bandwidth" do
      Dir.mktmpdir do |dir|
        build_package(dir)
        p = playlists_for(dir)
        audio = p.measure("audio.m3u8")
        video = p.measure("720p.m3u8")
        p.write_all
        text = File.read(File.join(dir, "index.m3u8"))
        # a player fetches a rung AND the audio rendition, so the wire rate is the sum
        _(text).must_include "BANDWIDTH=#{video[:peak] + audio[:peak]}"
        _(text).must_include "AVERAGE-BANDWIDTH=#{video[:average] + audio[:average]}"
      end
    end

    it "declares the audio group, CLOSED-CAPTIONS and the trickplay variant" do
      Dir.mktmpdir do |dir|
        build_package(dir)
        playlists_for(dir).write_all
        text = File.read(File.join(dir, "index.m3u8"))
        _(text).must_include %(#EXT-X-MEDIA:TYPE=AUDIO,GROUP-ID="group_audio")
        _(text).must_include %(LANGUAGE="en")
        _(text).must_include "#EXT-X-INDEPENDENT-SEGMENTS"
        _(text).must_include "#EXT-X-I-FRAME-STREAM-INF:"
        _(text.scan("CLOSED-CAPTIONS=NONE").length).must_be :>=, 1
        # every video variant references the audio group
        video_lines = text.lines.select { |l| l.start_with?("#EXT-X-STREAM-INF") && l.include?("RESOLUTION") }
        _(video_lines.length).must_equal 2
        video_lines.each { |l| _(l).must_include %(AUDIO="group_audio") }
      end
    end

    it "declares media playlists in the order given, tallest first" do
      Dir.mktmpdir do |dir|
        build_package(dir)
        playlists_for(dir).write_all
        text = File.read(File.join(dir, "index.m3u8"))
        _(text.index("720p.m3u8")).must_be :<, text.index("480p.m3u8")
      end
    end

    it "declares no EXT-X-INDEPENDENT-SEGMENTS in the media playlists" do
      Dir.mktmpdir do |dir|
        build_package(dir)
        playlists_for(dir).write_all
        %w[720p.m3u8 audio.m3u8 iframe.m3u8].each do |pl|
          _(File.read(File.join(dir, pl))).wont_include "#EXT-X-INDEPENDENT-SEGMENTS"
        end
      end
    end
  end
end
