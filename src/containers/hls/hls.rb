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
require_relative "telemetry"
require_relative "destinations/aws/s3"
require_relative "lib/encoders"
require_relative "presets/standard_podcast_2026_v1"
require_relative "lib/edits"
require_relative "lib/boundaries"
require_relative "lib/ffmpeg"
require_relative "lib/ts_packer"
require_relative "lib/playlists"
require_relative "lib/break_report"

sf = Aws::States::Client.new

begin
  get_artifact_s3tm = Aws::S3::TransferManager.new

  task = JSON.parse(ENV["STATE_MACHINE_TASK_JSON"])

  # For now, always use this
  preset = Presets::StandardPodcast2026::V1
  raise StandardError, "Unsupported preset" unless task["Preset"] == preset::NAME

  # The encoder is a property of where this task is run (not of the request)
  # unrecognized or unavailable encoders raise rather than quietly using the CPU
  # i.e. if this isn't working, we should fix the deployment & config
  encoder = Hls::Encoders.resolve(ENV["HLS_VIDEO_ENCODER"]) || preset::VIDEO_ENCODER.new
  unless encoder.available?
    raise StandardError, "video encoder #{encoder.codec} is unavailable: #{encoder.unavailable_reason}"
  end

  # Ad breaks, and sections to remove (see Hls::Edits), in seconds from the start of the asset.
  # breaks are optional: with none specified, the segment layout is the plain grid
  # and no break metadata is reported.
  # Each break becomes a segment boundary and keyframe, quantized to a whole frame, so
  # what comes back in the response's AdBreaks may differ slightly from what was asked for.
  ad_break_entries = Hls::Edits.parse(task["AdBreaks"])

  # Get the artifact file from S3
  puts "Downloading artifact"
  artifact_bucket = ENV["STATE_MACHINE_ARTIFACT_BUCKET_NAME"]
  artifact_key = ENV["STATE_MACHINE_ARTIFACT_OBJECT_KEY"]
  get_artifact_s3tm.download_file("artifact.file", bucket: artifact_bucket, key: artifact_key)

  puts JSON.dump({msg: "Starting task…"})
  send_start_metric
  start_time = Time.now.to_i

  task_result = {
    Task: ENV["STATE_MACHINE_TASK_TYPE"],
    BucketName: ENV["STATE_MACHINE_DESTINATION_BUCKET_NAME"],
    ObjectKeyPrefix: ENV["STATE_MACHINE_DESTINATION_OBJECT_KEY_PREFIX"],
    Preset: {
      Name: preset::NAME,
      Encoder: encoder.codec,
      PossibleLabels: preset::POSSIBLE_LABELS
    },
    Assets: {}
  }

  work = preset::WORK_DIR
  audio_parts = File.join(work, preset::AUDIO_PARTS_DIR)
  FileUtils.rm_rf(work)
  FileUtils.mkdir_p(audio_parts)

  duration = Hls::Probe.value("artifact.file", "format=duration").to_f
  source_height = Hls::Probe.value("artifact.file", "stream=height", stream: "v:0").to_i
  source_fps = Hls::Probe.value("artifact.file", "stream=r_frame_rate", stream: "v:0")
  raise StandardError, "Artifact has no video stream" if source_height.zero?
  raise StandardError, "Could not determine artifact duration" unless duration.positive?

  # No rungs? that's an error
  # Rungs taller than the source? Dropped (and logged) rather than upscaled.
  rungs, skipped = Hls::FFmpeg.select_rungs(preset::RUNGS, source_height)
  if rungs.empty?
    raise StandardError, "No rungs at or below the source height (#{source_height}p)"
  end
  # Otherwise ffmpeg fails to map the audio and reports only that it failed.
  if Hls::Probe.value("artifact.file", "stream=codec_type", stream: "a:0").empty?
    raise StandardError, "Artifact has no audio stream"
  end
  puts JSON.dump({
    msg: "Source inspected",
    duration: duration,
    height: source_height,
    source_fps: source_fps,
    output_fps: preset::FPS,
    encoding: rungs.map { |r| r[:height] },
    skipped_as_upscale: skipped,
    ad_breaks_requested: task["AdBreaks"]
  })

  # From here on, every time is in the edited timeline.
  edit = Hls::Edits.build(ad_break_entries, duration: duration, fps: preset::FPS)
  if edit.cut?
    puts JSON.dump({
      msg: "Cutting source",
      keep: edit.keep.map { |from, to| [Hls::Timing.round6(from), to && Hls::Timing.round6(to)] },
      edited_duration: Hls::Timing.round6(edit.duration),
      trims: edit.trims.map { |t| {position: t.position, removed: Hls::Timing.round6(t.removed)} }
    })
  end

  # One boundary set, three views of it (mostly to work with ffmpeg).
  # They differ only in rounding:
  # video keyframes are biased half a frame early so ffmpeg picks the intended frame,
  # audio splits use the exact times, and the break times are reported as-is.
  # audio_grain is one audio frame in seconds (maybe calculate in boundaries instead?)
  begin
    layout = Hls::Boundaries.build(
      duration: edit.duration,
      target: preset::TARGET,
      fps: preset::FPS,
      hls_time: preset::HLS_TIME,
      breaks: edit.breaks.map(&:boundary_time),
      max_seg: preset::MAX_SEG,
      min_segment: preset::MIN_SEGMENT,
      audio_grain: Rational(preset::AUDIO_FRAME_SAMPLES, preset::AUDIO_SAMPLE_RATE.to_i)
    )
  rescue RuntimeError => e
    raise unless edit.cut?
    # Its times are edited-timeline times, which a caller thinking in source time
    # would not recognize.
    raise e.class, "#{e.message} Times are in the edited timeline, after removing " \
                   "#{Hls::Timing.round6(edit.removed)}s of AdBreaks ranges."
  end

  ffmpeg_cmd = Hls::FFmpeg.new(
    input: "artifact.file",
    dir: work,
    rungs: rungs,
    layout: layout,
    settings: preset,
    audio_parts: audio_parts,
    encoder: encoder,
    keep: edit.keep
  ).command

  puts JSON.dump({msg: "Running FFmpeg", full_command: ffmpeg_cmd})
  ff_stdout, ff_stderr, ff_status = Open3.capture3(*ffmpeg_cmd)
  unless ff_status.success?
    tail = ff_stderr.lines.last(20).join.strip
    raise StandardError, "FFmpeg failed (exit #{ff_status.exitstatus}): #{tail}"
  end
  puts JSON.dump({msg: "FFmpeg finished", stderr_tail: ff_stderr.lines.last(5).join.strip})

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
  rung_segments = rungs.to_h do |r|
    ["#{r[:height]}p", Hls::MediaPlaylist.segments(File.join(work, "#{r[:height]}p.m3u8"))]
  end
  counts = rung_segments.transform_values(&:size)
  if counts.values.uniq.length > 1
    raise StandardError, "video rungs disagree on segment count: #{counts.inspect}. " \
                         "Every rung gets the same keyframe list, so they must match."
  end
  encoded = rung_segments.values.first.sum(&:duration)
  # Compared against the edited duration: the layout was computed for that.
  # One second covers final-frame rounding (0.095s on a 54-minute asset) without
  # tolerating a missing segment.
  expected_duration = edit.duration.to_f
  if (encoded - expected_duration).abs > 1.0
    edited = edit.cut? ? " once the AdBreaks ranges are removed" : ""
    raise StandardError, "encoded duration #{format("%.3f", encoded)}s does not match " \
                         "the source's #{format("%.3f", expected_duration)}s#{edited}. The " \
                         "source is probably truncated or its header duration is wrong; " \
                         "the break layout was computed for the latter."
  end
  puts JSON.dump({
    msg: "Outputs verified",
    segments: counts.values.first,
    encoded_duration: encoded.round(3),
    source_duration: duration.round(3),
    expected_duration: expected_duration.round(3)
  })

  # ffmpeg's own (not so great) master playlist is discarded; see lib/playlists.rb.
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

  # Same boundary list as the video keyframes, so the counts must match or
  # InsertAfterSegmentIndex differs between playlists. The rung check above misses an
  # encoder adding keyframes of its own (videotoolbox has, after dropping frames).
  if ranges != counts.values.first
    raise StandardError, "audio has #{ranges} segments but video has #{counts.values.first}. " \
                         "The video encoder likely added keyframes of its own."
  end

  rendition = Hls::Playlists::Rendition
  video_renditions = rungs.map do |r|
    rendition.new(playlist: "#{r[:height]}p.m3u8", media: "#{r[:height]}p.ts", label: preset.rung_label(r[:height]))
  end
  audio_rendition = rendition.new(playlist: preset::AUDIO_PLAYLIST, media: preset::AUDIO_MEDIA, label: "AUDIO")
  iframe_rendition = rendition.new(playlist: preset::IFRAME_PLAYLIST, media: preset::IFRAME_MEDIA, label: "IFRAME")

  # Wall-clock anchor for EXT-X-PROGRAM-DATE-TIME. VOD has no real wall clock, so
  # this is the packaging time -- what matters is that one value goes into every
  # media playlist, and that the caller gets it back to compute interstitial
  # START-DATEs from the break times without refetching a playlist,
  # you know, once we add in the interstitials.
  program_date_time = Time.now.utc.strftime("%Y-%m-%dT%H:%M:%S.%LZ")

  playlist_result = Hls::Playlists.new(
    dir: work,
    video_rungs: video_renditions,
    audio: audio_rendition,
    iframe: iframe_rendition,
    settings: preset,
    program_date_time: program_date_time,
    breaks: layout.breaks.map { |b| b.at.to_f }
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
  unless edit.breaks.empty?
    task_result[:AdBreaks] = Hls::BreakReport.build(
      Hls::Edits.placed(edit, layout),
      File.join(work, video_renditions.first.playlist),
      # Half a frame at the output rate: further means a different frame.
      tolerance: 1.0 / (2 * Rational(preset::FPS))
    )
  end

  # Only when something was cut, so results for point-only jobs keep their shape.
  if edit.cut?
    task_result[:Duration] = Hls::Timing.round6(encoded)
    unless edit.trims.empty?
      task_result[:Trims] = edit.trims.map do |t|
        {RequestedTime: Hls::BreakReport.requested_formatted(t.requested), RemovedDuration: Hls::Timing.round6(t.removed)}
      end
    end
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
  # Logs on any failure once ffmpeg has run, including a clean exit with bad outputs.
  if ff_status
    puts JSON.dump({
      msg: "FFmpeg output",
      exit_status: ff_status.exitstatus,
      stdout: ff_stdout,
      stderr: ff_stderr
    })
  end

  sf.send_task_failure({
    task_token: ENV["STATE_MACHINE_TASK_TOKEN"],
    error: e.class.name,
    # Without this the caller sees only "RuntimeError", while the messages raised
    # here name the setting to change. Truncated because SendTaskFailure caps cause
    # at 32768 characters.
    cause: e.message.to_s[0, 32_000]
  })
end
