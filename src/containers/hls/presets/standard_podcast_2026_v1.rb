# frozen_string_literal: true

module Presets
  module StandardPodcast2026
    # Encoding and packaging settings, so hls.rb stays orchestration only.
    class V1
      NAME = "Standard Podcast 2026 v1"

      POSSIBLE_LABELS = %w[AUDIO 480P 720P 1080P IFRAME].freeze

      RUNGS = [
        {height: 1080, size: "1920x1080", bitrate: "5000k"},
        {height: 720, size: "1280x720", bitrate: "2800k"},
        {height: 480, size: "854x480", bitrate: "1200k"}
      ].freeze

      PRESET = "medium"

      # Every rung is normalized to this, and the boundary math is quantized against it
      # TODO: think about if this should be 23.976 or 24 fps, or different preset?
      FPS = "30"

      # Target segment duration (not HLS_TIME; TARGET > HLS_TIME)
      TARGET = 6

      # Used in the call to ffmpeg for the -hls_time option,
      # but the TARGET and keyframes actually set the segment grid/cadence.
      # Also the earliest a break can be placed: the muxer's split target starts
      # here and advances by this much per segment.
      HLS_TIME = 1

      # Shortest segment we will author. Boundaries defaults this to HLS_TIME; they
      # are set apart so HLS_TIME can stay low (early breaks reachable) without
      # lowering the quality floor. Never set below HLS_TIME -- surviving grid points
      # then eat cumulative slots ahead of a break and make it unreachable.
      MIN_SEGMENT = 2

      # Maximum segment length, and so the maximum keyframe interval
      MAX_SEG = TARGET

      # Inclusive. Failing beats shipping a playlist a distribution target rejects.
      TARGET_DURATION_RANGE = (6..10)

      # AUDIO
      AUDIO_BITRATE = "192k"
      AUDIO_SAMPLE_RATE = "48000"
      AUDIO_CODEC = "mp4a.40.2"

      AUDIO_FRAME_SAMPLES = 1024
      AUDIO_CHANNELS = "2"
      AUDIO_LANGUAGE = "en"

      ## IFRAME
      # I-frame-only variant for scrubbing: every frame an IDR, one per segment.
      IFRAME_FPS = 2

      # Only ever shown as scrub thumbnails, so 240p rather than matching a rung.
      IFRAME_SIZE = "426x240"
      IFRAME_BITRATE = "150k"

      # Tenths, so 15 = 1.5x. Required: all-IDR content is spiky enough that an
      # uncapped encode peaks well over twice its own average, which gets flagged.
      IFRAME_MAXRATE_FACTOR = 15

      ## Playlists
      # Byteranges only need v4, but higher is needed for the master
      MULTIVARIANT_VERSION = 4
      MEDIA_PLAYLIST_VERSION = 7

      # Video rungs are named by height (1080p.ts, 1080p.m3u8) via ffmpeg's %v.
      AUDIO_PLAYLIST = "audio.m3u8"
      AUDIO_MEDIA = "audio.ts"
      IFRAME_PLAYLIST = "iframe.m3u8"
      IFRAME_MEDIA = "iframe.ts"
      MASTER_PLAYLIST = "index.m3u8"

      # Compatibility version (identical but for the audio-only variant)
      COMPAT_MASTER_PLAYLIST = "index-compat.m3u8"

      # ffmpeg needs a master for a var_stream_map output
      # Ours replaces it, so this is written and deleted.
      FFMPEG_RAW_MASTER = "ffmpeg-raw.m3u8"

      # Holds the segment muxer's audio parts until TsPacker joins them.
      AUDIO_PARTS_DIR = "_audio_parts"

      WORK_DIR = "hls"

      def self.rung_label(height)
        "#{height}P"
      end
    end
  end
end
