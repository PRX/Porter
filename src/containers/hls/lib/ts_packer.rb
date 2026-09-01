# frozen_string_literal: true

require "json"

module Hls
  # Concatenates `segment` muxer output into one file plus a byterange playlist.
  #
  # `-hls_flags single_file` lives only on ffmpeg's `hls` muxer, and that muxer
  # cannot split an audio-only rendition where we need it to: every audio frame is a
  # keyframe, so nothing narrows the split to our boundaries and hls_time alone
  # drives it (measured, and the same in fMP4, so it is the muxer not the
  # container). The audio rendition therefore comes from the `segment` muxer, which
  # does honor an explicit -segment_times list, and this class stitches its parts
  # into the single-file + byterange shape the rest of the package uses.
  #
  # Concatenating is safe because the `segment` muxer writes a full PAT/PMT at the
  # head of every part (-individual_header_trailer defaults to true), which is what
  # byterange HLS needs: a player may fetch range N without ever fetching N-1.
  class TsPacker
    TS_PACKET = 188
    SYNC_BYTE = 0x47
    NULL_PID = 0x1FFF

    def initialize(parts_playlist:, out_media:, out_playlist:, version:)
      @parts_playlist = parts_playlist
      @out_media = out_media
      @out_playlist = out_playlist
      @version = version
      @base = File.dirname(parts_playlist)
    end

    # Returns the number of ranges written.
    def pack
      entries = read_parts
      raise "no segments found in #{@parts_playlist}" if entries.empty?

      counters = {}
      offset = 0
      longest = 0.0
      body = []
      unaligned = false

      File.open(@out_media, "wb") do |sink|
        entries.each do |duration, name|
          data = File.binread(File.join(@base, name))
          data, aligned = renumber_continuity(data, counters)
          unaligned ||= !aligned
          sink.write(data)

          body << format("#EXTINF:%.6f,", duration)
          body << "#EXT-X-BYTERANGE:#{data.bytesize}@#{offset}"
          body << File.basename(@out_media)

          offset += data.bytesize
          longest = duration if duration > longest
        end
      end

      if unaligned
        puts JSON.dump({
          msg: "WARNING: a part was not TS packet aligned; continuity " \
               "counters were only partly renumbered",
          packet_size: TS_PACKET
        })
      end

      write_playlist(body, longest)
      entries.length
    end

    # Rewrite MPEG-TS continuity counters so they run continuously.
    #
    # Every part restarts its per-PID continuity_counter at 0, so a player sees one
    # discontinuity per PID per join.
    # ffmpeg tolerates that silently (-err_detect explode reports nothing) but VLC drops audio.
    # It is not an artifact of concatenating: using the segment muxer's files
    # directly as multi-file segments produces the same errors, because players track
    # continuity across HLS segments. Any use of the `segment` muxer needs this.
    #
    # Per ISO 13818-1 the counter increments only on packets carrying a payload
    # (adaptation_field_control 1 or 3), so adaptation-only packets keep the last
    # value and null packets are left alone. Renumbering globally is safe for
    # byterange playback: a client fetching one range mid-file sees an arbitrary
    # starting value and correct increments from there.
    #
    # Returns [data, aligned]. `counters` is carried across calls so the sequence
    # continues over part boundaries.
    def renumber_continuity(data, counters)
      buf = data.dup
      packets = buf.bytesize / TS_PACKET
      # The segment muxer always writes complete packets, so this should not
      # happen. Trailing bytes are still copied verbatim and counted in the
      # byterange, but the walk cannot renumber them, so surface it.
      aligned = (buf.bytesize % TS_PACKET).zero?

      packets.times do |i|
        off = i * TS_PACKET
        if buf.getbyte(off) != SYNC_BYTE
          # Not packet-aligned; leave the rest alone rather than corrupt it.
          aligned = false
          break
        end

        pid = ((buf.getbyte(off + 1) & 0x1F) << 8) | buf.getbyte(off + 2)
        next if pid == NULL_PID

        byte3 = buf.getbyte(off + 3)
        afc = (byte3 >> 4) & 0x03

        if afc == 1 || afc == 3
          counters[pid] = ((counters[pid] || -1) + 1) & 0x0F
        elsif !counters.key?(pid)
          next    # no payload yet and nothing seen for this PID
        end

        buf.setbyte(off + 3, (byte3 & 0xF0) | counters[pid])
      end

      [buf, aligned]
    end

    # Not used in the pipeline -- exists so tests and the verification steps can
    # assert zero without reimplementing the packet walk.
    def self.count_discontinuities(path)
      data = File.binread(path)
      last = {}
      breaks = 0
      (data.bytesize / TS_PACKET).times do |i|
        off = i * TS_PACKET
        break unless data.getbyte(off) == SYNC_BYTE
        pid = ((data.getbyte(off + 1) & 0x1F) << 8) | data.getbyte(off + 2)
        next if pid == NULL_PID
        byte3 = data.getbyte(off + 3)
        next unless [1, 3].include?((byte3 >> 4) & 0x03)
        cc = byte3 & 0x0F
        breaks += 1 if last.key?(pid) && cc != ((last[pid] + 1) & 0x0F)
        last[pid] = cc
      end
      breaks
    end

    private

    # Each part's duration, in order. Trust the segment muxer's own EXTINF values
    # rather than recomputing -- it knows the real packet timing.
    def read_parts
      entries = []
      duration = nil
      File.foreach(@parts_playlist) do |line|
        line = line.strip
        if (m = line.match(/\A#EXTINF:([\d.]+)/))
          duration = m[1].to_f
        elsif !line.empty? && !line.start_with?("#") && duration
          entries << [duration, line]
          duration = nil
        end
      end
      entries
    end

    def write_playlist(body, longest)
      header = [
        "#EXTM3U",
        "#EXT-X-VERSION:#{@version}",
        # rounded & provisional: Playlists.harmonize_target_duration rewrites it in all renditions to a single number.
        "#EXT-X-TARGETDURATION:#{longest.round}",
        "#EXT-X-PLAYLIST-TYPE:VOD",
        "#EXT-X-MEDIA-SEQUENCE:0"
      ]
      File.write(@out_playlist, (header + body + ["#EXT-X-ENDLIST", ""]).join("\n"))
    end
  end
end
