# frozen_string_literal: true

require "json"

module Hls
  # Writes the master playlists
  # `ffmpeg`'s own master is not quite right:
  # - it declares bandwidth from video alone, leaving out the audio rate
  # - it omits the audio-only variant
  # - it omits the CLOSED-CAPTIONS attribute
  class Playlists
    AUDIO_GROUP = "group_audio"
    AUDIO_NAME = "Main"

    # MPEG-TS packet size, and the PIDs making up the Media Initialization
    # Section (PAT, SDT, PMT). Used to measure the init prefix for EXT-X-MAP.
    TS_PACKET = 188
    TS_INIT_PIDS = [0x0000, 0x0011, 0x1000].freeze

    # H.264 profile_idc values, hex, for the avc1.PPCCLL codec string.
    PROFILE_IDC = {
      "Baseline" => "42",
      "Constrained Baseline" => "42",
      "Main" => "4D",
      "High" => "64",
      "High 10" => "6E"
    }.freeze

    Rendition = Struct.new(:playlist, :media, :label)

    # dir               -- output directory holding the media playlists
    # video_rungs       -- [Rendition] tallest first
    # audio             -- Rendition for the shared audio rendition
    # iframe            -- Rendition for the trickplay variant
    # settings          -- the preset (see presets/*.rb)
    # program_date_time -- ISO8601 wall-clock anchor for the first sample, for interstitials
    def initialize(dir:, video_rungs:, audio:, iframe:, settings:, program_date_time:)
      @dir = dir
      @video_rungs = video_rungs
      @audio = audio
      @iframe = iframe
      @s = settings
      @pdt = program_date_time
    end

    # Writes both masters and normalizes the media playlists. Returns a Hash of
    # what it did, for logging and the task result.
    def write_all
      target_duration = harmonize_target_duration
      lifted = raise_media_versions
      stamp_program_date_time
      iframe_info = finalize_iframe_playlist

      audio_rate = measure(@audio.playlist)
      video = @video_rungs.map do |rung|
        {rendition: rung, rate: measure(rung.playlist), props: video_properties(rung.media)}
      end
      video.each do |v|
        raise "#{v[:rendition].playlist} has no video stream" if v[:props].nil?
      end
      iframe_rate = measure(@iframe.playlist)
      iframe_props = video_properties(@iframe.media)
      raise "#{@iframe.media} has no video stream" if iframe_props.nil?

      if iframe_rate[:peak] > 2 * iframe_rate[:average]
        # Advisory, but it means the trickplay encode was not rate capped.
        puts JSON.dump({
          msg: "WARNING: trickplay peak is more than twice its average; " \
               "tighten the trickplay rate cap",
          peak_kbps: iframe_rate[:peak] / 1000,
          average_kbps: iframe_rate[:average] / 1000
        })
      end

      # output the default master w/audio variant; compatibility master w/o
      write(@s::MASTER_PLAYLIST,
        master(video, audio_rate, iframe_rate, iframe_props, audio_only: true))
      write(@s::COMPAT_MASTER_PLAYLIST,
        master(video, audio_rate, iframe_rate, iframe_props, audio_only: false))

      {
        target_duration: target_duration,
        program_date_time: @pdt,
        versions_lifted: lifted,
        iframe: iframe_info.merge(
          resolution: iframe_props[:resolution], frame_rate: iframe_props[:frame_rate],
          average_kbps: iframe_rate[:average] / 1000
        )
      }
    end

    # Peak and average bitrate, straight from EXTINF + EXT-X-BYTERANGE. Reading
    # the byterange lengths is exact and cheap -- no need to re-probe the media.
    # Peak is the worst single segment, which is what BANDWIDTH means.
    def measure(playlist)
      duration = nil
      peak = 0
      total_duration = 0.0
      total_bytes = 0

      File.foreach(File.join(@dir, playlist)) do |line|
        if (m = line.match(/\A#EXTINF:([\d.]+)/))
          duration = m[1].to_f
        elsif (m = line.match(/\A#EXT-X-BYTERANGE:(\d+)@/)) && duration
          bytes = m[1].to_i
          rate = bytes * 8 / duration
          peak = rate if rate > peak
          total_duration += duration
          total_bytes += bytes
          duration = nil
        end
      end
      raise "#{playlist} has no byterange segments" if total_duration.zero?

      {peak: peak.to_i, average: (total_bytes * 8 / total_duration).to_i}
    end

    private

    # Force one TARGETDURATION across all renditions. They can disagree, because
    # two writers produce them -- ffmpeg for the video rungs, TsPacker for audio --
    # and neither can be told to match the other: ffmpeg has no target-duration
    # option, and TsPacker cannot emit a value below its own longest EXTINF.
    #
    # So take the maximum requirement and apply it everywhere, which is legal:
    # TARGETDURATION only has a lower bound. Rounding is half-UP, since a client
    # rounding that way would reject the smaller value.
    #
    # Trickplay is excluded -- its segments are single frames, so it has its own
    # small TARGETDURATION and must not be dragged up.
    def harmonize_target_duration
      playlists = @video_rungs.map(&:playlist) + [@audio.playlist]
      target = playlists.map { |pl| required_target_duration(pl) }.max

      range = @s::TARGET_DURATION_RANGE
      unless range.cover?(target)
        raise "EXT-X-TARGETDURATION is #{target}s, outside the allowed range " \
              "#{range.min}-#{range.max}s. Adjust TARGET (and HLS_TIME, which is " \
              "the min_segment floor that evicts grid points near a break and so " \
              "lengthens the adjacent segment)."
      end

      playlists.each do |pl|
        rewrite(pl) { |t| t.sub(/#EXT-X-TARGETDURATION:\d+/, "#EXT-X-TARGETDURATION:#{target}") }
      end
      target
    end

    # One anchor, byte-identical in every media playlist. A rendition carrying a
    # different value would resolve the same START-DATE to a different media time.
    # Inserted before the first EXTINF, which is what makes it apply to the first
    # segment, and is the one position every writer here agrees on.
    def stamp_program_date_time
      tag = "#EXT-X-PROGRAM-DATE-TIME:#{@pdt}"
      media_playlists.each do |pl|
        rewrite(pl) do |text|
          raise "#{pl} has no segments to anchor" unless text.include?("#EXTINF:")

          if text.include?("#EXT-X-PROGRAM-DATE-TIME")
            text.sub(/#EXT-X-PROGRAM-DATE-TIME:\S*/, tag)
          else
            text.sub("#EXTINF:", "#{tag}\n#EXTINF:")
          end
        end
      end
    end

    def media_playlists
      @video_rungs.map(&:playlist) + [@audio.playlist, @iframe.playlist]
    end

    def required_target_duration(playlist)
      longest = 0.0
      File.foreach(File.join(@dir, playlist)) do |line|
        if (m = line.match(/\A#EXTINF:([\d.]+)/))
          v = m[1].to_f
          longest = v if v > longest
        end
      end
      half_up(longest)
    end

    # Explicit, so it does not look like an accident of Float#round's default.
    def half_up(value)
      (value + 0.5).floor
    end

    # Lift each media playlist's EXT-X-VERSION to the floor. Only ever raise --
    # never lower one a playlist earned by using a newer tag. The floor is not
    # discoverable from the tags in use; 4 is technically correct here.
    def raise_media_versions
      lifted = []
      media_playlists.each do |pl|
        text = File.read(File.join(@dir, pl))
        m = text.match(/#EXT-X-VERSION:(\d+)/)
        raise "#{pl} has no EXT-X-VERSION tag" if m.nil?
        next if m[1].to_i >= @s::MEDIA_PLAYLIST_VERSION

        rewrite(pl) { |t| t.sub(m[0], "#EXT-X-VERSION:#{@s::MEDIA_PLAYLIST_VERSION}") }
        lifted << "#{pl} #{m[1]}->#{@s::MEDIA_PLAYLIST_VERSION}"
      end
      lifted
    end

    # ffmpeg has no option to emit an I-frames-only playlist, so it writes an
    # ordinary media playlist and we annotate it. Three edits:
    #
    #   - EXT-X-I-FRAMES-ONLY: what lets a player use this for scrubbing.
    #   - EXT-X-MAP: required for an I-frames-only playlist, and ffmpeg does not
    #     write one for TS output. Its byterange overlaps the first segment's range,
    #     which is accepted, so ffmpeg's ranges are left untouched.
    #   - TARGETDURATION: ffmpeg writes 0 for half-second segments. Zero is not a
    #     usable duration, so floor it at 1.
    def finalize_iframe_playlist
      init_length = ts_init_section_length(@iframe.media)
      target = [1, required_target_duration(@iframe.playlist)].max

      rewrite(@iframe.playlist) do |text|
        text = text.sub(/#EXT-X-TARGETDURATION:\d+/, "#EXT-X-TARGETDURATION:#{target}")
        inserts = []
        inserts << "#EXT-X-I-FRAMES-ONLY" unless text.include?("#EXT-X-I-FRAMES-ONLY")
        unless text.include?("#EXT-X-MAP")
          inserts << %(#EXT-X-MAP:URI="#{@iframe.media}",BYTERANGE="#{init_length}@0")
        end
        unless inserts.empty?
          text = text.sub("#EXT-X-PLAYLIST-TYPE:VOD",
            (["#EXT-X-PLAYLIST-TYPE:VOD"] + inserts).join("\n"))
        end
        text
      end

      {target_duration: target, init_section_bytes: init_length}
    end

    # Byte length of the leading PAT/PMT/SDT packets: the Media Initialization
    # Section EXT-X-MAP points at. For TS that is not a separate object, just the
    # first few 188-byte packets carrying the program tables, so walk from the start
    # while the PID is a table PID and stop at the first ES packet. Read-only.
    def ts_init_section_length(media)
      head = File.binread(File.join(@dir, media), TS_PACKET * 32)
      length = 0
      (head.bytesize / TS_PACKET).times do |i|
        off = i * TS_PACKET
        break unless head.getbyte(off) == 0x47
        pid = ((head.getbyte(off + 1) & 0x1F) << 8) | head.getbyte(off + 2)
        break unless TS_INIT_PIDS.include?(pid)
        length = off + TS_PACKET
      end
      if length.zero?
        raise "#{media}: no PAT/PMT at the start; cannot build EXT-X-MAP for the " \
              "trickplay playlist"
      end
      length
    end

    # Per-variant video attributes read off the encoded stream, or nil for an
    # audio-only rendition.
    def video_properties(media)
      # Array form, not backticks: no shell, so a path with spaces or shell
      # metacharacters cannot break or be injected.
      out = IO.popen([
        "ffprobe", "-v", "error", "-select_streams", "v:0", "-show_entries",
        "stream=width,height,profile,level,r_frame_rate,color_transfer",
        "-of", "default=nw=1:nk=0", File.join(@dir, media),
        err: File::NULL
      ], &:read)
      fields = out.lines.filter_map do |l|
        k, _, v = l.strip.partition("=")
        [k, v] unless v.empty?
      end.to_h
      return nil if fields["width"].nil?

      idc = PROFILE_IDC.fetch(fields["profile"], "64")
      # level is tenths (31 == 3.1) and goes in as two hex digits (31 -> 1F).
      level = format("%02X", fields["level"].to_i)

      num, _, den = fields.fetch("r_frame_rate", "0/1").partition("/")
      den = "1" if den.empty?
      frame_rate = den.to_i.zero? ? nil : num.to_f / den.to_i

      # Read the transfer characteristics rather than asserting SDR, so an HDR
      # source that slips through is not mislabeled.
      video_range = case fields["color_transfer"]
      when "smpte2084" then "PQ"
      when "arib-std-b67" then "HLG"
      else "SDR"
      end

      {
        resolution: "#{fields["width"]}x#{fields["height"]}",
        codec: "avc1.#{idc}00#{level}",
        frame_rate: frame_rate,
        video_range: video_range
      }
    end

    def master(video, audio_rate, iframe_rate, iframe_props, audio_only:)
      lines = [
        "#EXTM3U",
        "#EXT-X-VERSION:#{@s::MULTIVARIANT_VERSION}",
        "#EXT-X-INDEPENDENT-SEGMENTS"
      ]

      # One audio rendition, referenced by every video variant via AUDIO=.
      lines << %(#EXT-X-MEDIA:TYPE=AUDIO,GROUP-ID="#{AUDIO_GROUP}",NAME="#{AUDIO_NAME}",) +
        %(LANGUAGE="#{@s::AUDIO_LANGUAGE}",DEFAULT=YES,AUTOSELECT=YES,) +
        %(CHANNELS="#{@s::AUDIO_CHANNELS}",URI="#{@audio.playlist}")

      video.each do |v|
        # The audio rate is ADDED: the player fetches a video rung AND the audio
        # rendition together, so the real rate on the wire is the sum.
        attrs = [
          "BANDWIDTH=#{v[:rate][:peak] + audio_rate[:peak]}",
          "AVERAGE-BANDWIDTH=#{v[:rate][:average] + audio_rate[:average]}",
          "RESOLUTION=#{v[:props][:resolution]}",
          # The audio codec belongs here even though the video playlist carries no
          # audio: CODECS describes what the player will decode for this variant.
          %(CODECS="#{v[:props][:codec]},#{@s::AUDIO_CODEC}"),
          "VIDEO-RANGE=#{v[:props][:video_range]}"
        ]
        attrs << format("FRAME-RATE=%.3f", v[:props][:frame_rate]) if v[:props][:frame_rate]
        attrs << %(AUDIO="#{AUDIO_GROUP}") << "CLOSED-CAPTIONS=NONE"
        lines << "#EXT-X-STREAM-INF:#{attrs.join(",")}"
        lines << v[:rendition].playlist
      end

      lines.concat(audio_only_variant(audio_rate)) if audio_only

      # Trickplay carries no AUDIO= and is not part of the ABR ladder, so it is
      # declared with its own tag rather than as an EXT-X-STREAM-INF.
      lines << "#EXT-X-I-FRAME-STREAM-INF:" + [
        "BANDWIDTH=#{iframe_rate[:peak]}",
        "AVERAGE-BANDWIDTH=#{iframe_rate[:average]}",
        "RESOLUTION=#{iframe_props[:resolution]}",
        %(CODECS="#{iframe_props[:codec]}"),
        %(URI="#{@iframe.playlist}")
      ].join(",")

      lines.join("\n") + "\n"
    end

    # Audio-only VARIANT, in addition to the EXT-X-MEDIA rendition, pointing at the
    # same playlist. Both are needed and not interchangeable: EXT-X-MEDIA makes audio
    # available in combination with a video variant, EXT-X-STREAM-INF makes it
    # independently selectable. ffmpeg's -var_stream_map cannot produce both, and
    # emitting the extra entry here costs no additional media.
    #
    # AUDIO= is required on it too -- dropping the attribute fails validation for
    # having no audio group at all.
    def audio_only_variant(audio_rate)
      [
        "#EXT-X-STREAM-INF:" + [
          "BANDWIDTH=#{audio_rate[:peak]}",
          "AVERAGE-BANDWIDTH=#{audio_rate[:average]}",
          %(CODECS="#{@s::AUDIO_CODEC}"),
          %(AUDIO="#{AUDIO_GROUP}"),
          "CLOSED-CAPTIONS=NONE"
        ].join(","),
        @audio.playlist
      ]
    end

    def rewrite(playlist)
      path = File.join(@dir, playlist)
      File.write(path, yield(File.read(path)))
    end

    # Write via a temp file and rename. A failure part-way through must not leave
    # a truncated master that looks like a successful run to anything downstream.
    def write(name, content)
      path = File.join(@dir, name)
      tmp = "#{path}.tmp"
      File.write(tmp, content)
      File.rename(tmp, path)
    end
  end
end
