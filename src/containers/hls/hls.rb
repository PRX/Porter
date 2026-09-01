#!/bin/ruby

# The following environment variables are passed in as ContainerOverrides when
# the state machine runs the ECS task
# STATE_MACHINE_ARN
# STATE_MACHINE_NAME
# STATE_MACHINE_EXECUTION_ID
# STATE_MACHINE_JOB_ID
# STATE_MACHINE_TASK_INDEX
# STATE_MACHINE_S3_DESTINATION_WRITER_ROLE
# STATE_MACHINE_AWS_REGION
# STATE_MACHINE_ARTIFACT_BUCKET_NAME
# STATE_MACHINE_ARTIFACT_OBJECT_KEY
# STATE_MACHINE_DESTINATION_JSON
# STATE_MACHINE_DESTINATION_MODE
# STATE_MACHINE_DESTINATION_BUCKET_NAME
# STATE_MACHINE_DESTINATION_OBJECT_KEY_PREFIX
# STATE_MACHINE_TASK_JSON
# STATE_MACHINE_ARTIFACT_JSON
# STATE_MACHINE_TASK_TOKEN
# STATE_MACHINE_TASK_TYPE

require "json"
require "time"
require "open3"
require "fileutils"
require "aws-sdk-states"
require "aws-sdk-s3"
load "./telemetry.rb"
load "./destinations/aws/s3.rb"
load "./presets/standard_podcast_2026_v1.rb"
load "./lib/boundaries.rb"
load "./lib/ffmpeg.rb"
load "./lib/ts_packer.rb"
load "./lib/playlists.rb"
load "./lib/break_report.rb"

sf = Aws::States::Client.new

# Probe a single value off the artifact. Array form, so no shell is involved.
def probe(file, entries, stream: nil)
  args = ["ffprobe", "-v", "error"]
  args += ["-select_streams", stream] if stream
  args += ["-show_entries", entries, "-of", "csv=p=0", file]
  IO.popen(args, &:read).lines.first.to_s.strip
end

begin
  get_artifact_s3tm = Aws::S3::TransferManager.new

  task = JSON.parse(ENV["STATE_MACHINE_TASK_JSON"])

  # For now, always use this
  preset = Presets::StandardPodcast2026::V1

  # Get the artifact file from S3
  puts "Downloading artifact"
  get_artifact_s3tm.download_file("artifact.file", bucket: ENV["STATE_MACHINE_ARTIFACT_BUCKET_NAME"], key: ENV["STATE_MACHINE_ARTIFACT_OBJECT_KEY"])

  raise StandardError, "Unsupported preset" unless task["Preset"] == preset::NAME

  # Ad break times, in seconds from the start of the asset. Optional: with none,
  # the segment layout is the plain grid and no break metadata is reported. Each
  # break becomes a segment boundary AND a keyframe, quantized to a whole frame, so
  # what comes back in AdBreaks may differ slightly from what was asked for.
  ad_breaks = Array(task["AdBreaks"]).map { |t| Float(t) }
  unless ad_breaks.all?(&:finite?) && ad_breaks.all?(&:positive?)
    raise StandardError, "AdBreaks must be positive numbers of seconds"
  end

  puts JSON.dump({msg: "Starting task…"})
  send_start_metric

  task_result = {
    Task: ENV["STATE_MACHINE_TASK_TYPE"],
    BucketName: ENV["STATE_MACHINE_DESTINATION_BUCKET_NAME"],
    ObjectKeyPrefix: ENV["STATE_MACHINE_DESTINATION_OBJECT_KEY_PREFIX"],
    Preset: {
      Name: preset::NAME,
      PossibleLabels: preset::POSSIBLE_LABELS
    },
    Assets: {}
  }

  start_time = Time.now.to_i

  work = preset::WORK_DIR
  audio_parts = File.join(work, preset::AUDIO_PARTS_DIR)
  FileUtils.rm_rf(work)
  FileUtils.mkdir_p(audio_parts)

  duration = probe("artifact.file", "format=duration").to_f
  source_height = probe("artifact.file", "stream=height", stream: "v:0").to_i
  source_fps = probe("artifact.file", "stream=r_frame_rate", stream: "v:0")
  raise StandardError, "Artifact has no video stream" if source_height.zero?
  raise StandardError, "Could not determine artifact duration" unless duration.positive?

  # Rungs taller than the source are dropped rather than upscaled. Logged, not
  # silent -- a distribution target may require a variant that got skipped, and then
  # the too-small source is what needs fixing.
  rungs, skipped = Hls::FFmpeg.select_rungs(preset::RUNGS, source_height)
  if rungs.empty?
    raise StandardError, "No rungs at or below the source height (#{source_height}p)"
  end
  puts JSON.dump({
    msg: "Source inspected",
    duration: duration, height: source_height, source_fps: source_fps,
    output_fps: preset::FPS,
    encoding: rungs.map { |r| r[:height] }, skipped_as_upscale: skipped,
    ad_breaks_requested: ad_breaks
  })

  # One boundary set, three views of it. They differ only in rounding: video
  # keyframes are biased half a frame early so ffmpeg picks the intended frame,
  # audio splits use the exact times, and the break times are reported as-is.
  # audio_grain is one audio frame in seconds
  layout = Hls::Boundaries.build(
    duration: duration, target: preset::TARGET, fps: preset::FPS,
    hls_time: preset::HLS_TIME, breaks: ad_breaks, max_seg: preset::MAX_SEG,
    min_segment: preset::MIN_SEGMENT,
    audio_grain: Rational(preset::AUDIO_FRAME_SAMPLES, preset::AUDIO_SAMPLE_RATE.to_i)
  )

  ffmpeg_cmd = Hls::FFmpeg.new(
    input: "artifact.file", dir: work, rungs: rungs, layout: layout,
    settings: preset, audio_parts: audio_parts
  ).command

  puts JSON.dump({msg: "Running FFmpeg", full_command: ffmpeg_cmd})
  # capture2e, not system: on failure ffmpeg's own diagnostics are the only useful
  # thing to report, and `system` leaves them where the task result cannot reach
  # them. Tail only -- a wall of output is not worth putting in a callback.
  ff_output, ff_status = Open3.capture2e(*ffmpeg_cmd)
  unless ff_status.success?
    tail = ff_output.lines.last(20).join.strip
    raise StandardError, "FFmpeg failed (exit #{ff_status.exitstatus}): #{tail}"
  end
  puts JSON.dump({msg: "FFmpeg finished", stderr_tail: ff_output.lines.last(5).join.strip})

  # ffmpeg can exit 0 having written nothing useful. Without this, the first sign
  # is an ENOENT from the packer or the upload, which reads like a bug here rather
  # than a failed encode.
  expected = rungs.map { |r| "#{r[:height]}p.ts" } +
    rungs.map { |r| "#{r[:height]}p.m3u8" } +
    [preset::IFRAME_MEDIA, preset::IFRAME_PLAYLIST,
      File.join(preset::AUDIO_PARTS_DIR, "parts.m3u8")]
  missing = expected.reject { |f| File.size?(File.join(work, f)) }
  unless missing.empty?
    raise StandardError, "FFmpeg exited 0 but these outputs are missing or empty: " \
                         "#{missing.join(", ")}"
  end

  # Present and non-empty is not enough: ffmpeg exits 0 on a truncated source and
  # simply encodes less of it, writing every file. The layout was computed for the
  # full duration, so breaks past the real content would be reported against
  # whatever boundary happened to be closest. Compare output against the plan.
  extinf_total = ->(playlist) {
    File.foreach(File.join(work, playlist)).sum { |l|
      (m = l.match(/\A#EXTINF:([\d.]+)/)) ? m[1].to_f : 0.0
    }
  }
  counts = rungs.to_h { |r| ["#{r[:height]}p", File.foreach(File.join(work, "#{r[:height]}p.m3u8")).count { |l| l.start_with?("#EXTINF:") }] }
  if counts.values.uniq.length > 1
    raise StandardError, "video rungs disagree on segment count: #{counts.inspect}. " \
                         "Every rung gets the same keyframe list, so they must match."
  end
  encoded = extinf_total.call("#{rungs.first[:height]}p.m3u8")
  # One second covers final-frame rounding (0.095s on a 54-minute asset) without
  # tolerating a missing segment.
  if (encoded - duration).abs > 1.0
    raise StandardError, "encoded duration #{format("%.3f", encoded)}s does not match " \
                         "the source's #{format("%.3f", duration)}s. The source is " \
                         "probably truncated or its header duration is wrong; the " \
                         "break layout was computed for the latter."
  end
  puts JSON.dump({msg: "Outputs verified", segments: counts.values.first,
                  encoded_duration: encoded.round(3), source_duration: duration.round(3)})

  # ffmpeg's own master playlist is discarded; see lib/playlists.rb.
  FileUtils.rm_f(File.join(work, preset::FFMPEG_RAW_MASTER))

  # The audio rendition comes out of the segment muxer as many parts, because that
  # is the only muxer that honors an explicit split list. Stitch them into the
  # single-file + byterange shape the other renditions use.
  ranges = Hls::TsPacker.new(
    parts_playlist: File.join(audio_parts, "parts.m3u8"),
    out_media: File.join(work, preset::AUDIO_MEDIA),
    out_playlist: File.join(work, preset::AUDIO_PLAYLIST),
    version: preset::MEDIA_PLAYLIST_VERSION
  ).pack
  FileUtils.rm_rf(audio_parts)
  puts JSON.dump({msg: "Audio rendition packed", ranges: ranges})

  rendition = Hls::Playlists::Rendition
  video_renditions = rungs.map do |r|
    rendition.new(playlist: "#{r[:height]}p.m3u8", media: "#{r[:height]}p.ts",
      label: preset.rung_label(r[:height]))
  end
  audio_rendition = rendition.new(playlist: preset::AUDIO_PLAYLIST,
    media: preset::AUDIO_MEDIA, label: "AUDIO")
  iframe_rendition = rendition.new(playlist: preset::IFRAME_PLAYLIST,
    media: preset::IFRAME_MEDIA, label: "IFRAME")

  # Wall-clock anchor for EXT-X-PROGRAM-DATE-TIME. VOD has no real wall clock, so
  # this is the packaging time -- what matters is that one value goes into every
  # media playlist, and that the caller gets it back to compute interstitial
  # START-DATEs from the break times without refetching a playlist.
  program_date_time = Time.now.utc.strftime("%Y-%m-%dT%H:%M:%S.%LZ")

  playlist_result = Hls::Playlists.new(
    dir: work, video_rungs: video_renditions, audio: audio_rendition,
    iframe: iframe_rendition, settings: preset, program_date_time: program_date_time
  ).write_all
  puts JSON.dump({msg: "Playlists written"}.merge(playlist_result))

  # --- upload and report ------------------------------------------------
  prefix = ENV["STATE_MACHINE_DESTINATION_OBJECT_KEY_PREFIX"]
  object_key = ->(name) { [prefix, name].join }
  upload = ->(name) { send_to_s3(File.join(work, name), name) }

  task_result[:Assets][:Variants] = []

  (video_renditions + [audio_rendition]).each do |r|
    upload.call(r.media)
    upload.call(r.playlist)
    task_result[:Assets][:Variants].push({
      PresetLabel: r.label,
      Playlist: {ObjectKey: object_key.call(r.playlist)},
      Media: {
        ObjectKey: object_key.call(r.media),
        IncludesAudioStreams: r == audio_rendition,
        IncludesVideoStreams: r != audio_rendition
      }
    })
  end

  # Declared with EXT-X-I-FRAME-STREAM-INF, never as a rung to switch to.
  upload.call(iframe_rendition.media)
  upload.call(iframe_rendition.playlist)
  task_result[:Assets][:Variants].push({
    PresetLabel: iframe_rendition.label,
    Playlist: {ObjectKey: object_key.call(iframe_rendition.playlist)},
    Media: {
      ObjectKey: object_key.call(iframe_rendition.media),
      IncludesAudioStreams: false,
      IncludesVideoStreams: true
    }
  })

  upload.call(preset::MASTER_PLAYLIST)
  task_result[:Assets][:MasterPlaylist] = {
    ObjectKey: object_key.call(preset::MASTER_PLAYLIST)
  }

  # Same renditions, minus the audio-only variant. See COMPAT_MASTER_PLAYLIST.
  upload.call(preset::COMPAT_MASTER_PLAYLIST)
  task_result[:Assets][:CompatibilityMasterPlaylist] = {
    ObjectKey: object_key.call(preset::COMPAT_MASTER_PLAYLIST)
  }

  # The anchor every media playlist carries. An interstitial's START-DATE is
  # wall clock, so a break at ActualTime seconds becomes this plus ActualTime.
  task_result[:ProgramDateTime] = program_date_time

  # Reported rather than written as a file: this is metadata about the encode, not
  # an asset, so the consuming app gets it without a second fetch.
  unless ad_breaks.empty?
    task_result[:AdBreaks] = Hls::BreakReport.build(
      layout.breaks,
      File.join(work, video_renditions.first.playlist),
      # Half a frame at the output rate: further means a different frame.
      tolerance: 1.0 / (2 * Rational(preset::FPS))
    )
  end

  end_time = Time.now.to_i
  elapsed = end_time - start_time

  now = Time.now
  task_result["Time"] = now.getutc.iso8601
  task_result["Timestamp"] = now.to_i

  puts JSON.dump({msg: "Task output", output: task_result})
  sf.send_task_success({
    task_token: ENV["STATE_MACHINE_TASK_TOKEN"],
    output: task_result.to_json
  })

  send_end_metric(elapsed)
  puts JSON.dump({msg: "Task complete; success has been reported to state machine"})
rescue => e
  puts JSON.dump({msg: "Task failed!", error: e.class.name, cause: e.message})
  puts e.backtrace

  sf.send_task_failure({
    task_token: ENV["STATE_MACHINE_TASK_TOKEN"],
    error: e.class.name,
    # Without this the caller sees only "RuntimeError", while the messages raised
    # here name the setting to change. Truncated because SendTaskFailure caps cause
    # at 32768 characters.
    cause: e.message.to_s[0, 32_000]
  })
end
