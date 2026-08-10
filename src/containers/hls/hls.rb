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
require "aws-sdk-states"
load "./telemetry.rb"
load "./destinations/aws/s3.rb"
load "./presets/standard_podcast_2026_v1.rb"

sf = Aws::States::Client.new

begin
  get_artifact_s3tm = Aws::S3::TransferManager.new

  # artifact = JSON.parse(ENV["STATE_MACHINE_ARTIFACT_JSON"])
  task = JSON.parse(ENV["STATE_MACHINE_TASK_JSON"])

  # For now, always use this
  preset = Presets::StandardPodcast2026::V1

  # Get the artifact file from S3
  puts "Downloading artifact"
  get_artifact_s3tm.download_file("artifact.file", bucket: ENV["STATE_MACHINE_ARTIFACT_BUCKET_NAME"], key: ENV["STATE_MACHINE_ARTIFACT_OBJECT_KEY"])

  raise StandardError, "Unsupported preset" unless task["Preset"] == preset::NAME

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

  ffmpeg_cmd = [
    "ffmpeg",
    "-hide_banner",
    "-loglevel warning",
    "-y",
    "-i artifact.file",
    "-filter_complex",
    [
      "[0:v]split=5[src_480p][src_720p][src_1080p][src_1440p][src_2160p]",
      "[src_480p]scale=854:480:flags=lanczos,fps=30,setsar=1[v_480p]",
      "[src_720p]scale=1280:720:flags=lanczos,fps=30,setsar=1[v_720p]",
      "[src_1080p]scale=1920:1080:flags=lanczos,fps=30,setsar=1[v_1080p]",
      "[src_1440p]scale=2560:1440:flags=lanczos,fps=30,setsar=1[v_1440p]",
      "[src_2160p]scale=3840:2160:flags=lanczos,fps=30,setsar=1[v_2160p]"
    ].join(";"),
    "-map [v_480p]",
    "-map [v_720p]",
    "-map [v_1080p]",
    "-map [v_1440p]",
    "-map [v_2160p]",
    "-map 0:a:0",
    "-pix_fmt yuv420p",

    "-c:v:0 libx264",
    "-preset:v:0 medium",
    "-profile:v:0 high",
    "-g:v:0 60",
    "-keyint_min:v:0 60",
    "-sc_threshold:v:0 0",
    "-b:v:0 1400k",
    "-maxrate:v:0 1498k",
    "-bufsize:v:0 2800k",

    "-c:v:1 libx264",
    "-preset:v:1 medium",
    "-profile:v:1 high",
    "-g:v:1 60",
    "-keyint_min:v:1 60",
    "-sc_threshold:v:1 0",
    "-b:v:1 2800k",
    "-maxrate:v:1 2996k",
    "-bufsize:v:1 5600k",

    "-c:v:2 libx264",
    "-preset:v:2 medium",
    "-profile:v:2 high",
    "-g:v:2 60",
    "-keyint_min:v:2 60",
    "-sc_threshold:v:2 0",
    "-b:v:2 5000k",
    "-maxrate:v:2 5350k",
    "-bufsize:v:2 10000k",

    "-c:v:3 libx264",
    "-preset:v:3 medium",
    "-profile:v:3 high",
    "-g:v:3 60",
    "-keyint_min:v:3 60",
    "-sc_threshold:v:3 0",
    "-b:v:3 8000k",
    "-maxrate:v:3 8560k",
    "-bufsize:v:3 16000k",

    "-c:v:4 libx264",
    "-preset:v:4 medium",
    "-profile:v:4 high",
    "-g:v:4 60",
    "-keyint_min:v:4 60",
    "-sc_threshold:v:4 0",
    "-b:v:4 25000k",
    "-maxrate:v:4 26750k",
    "-bufsize:v:4 50000k",

    "-force_key_frames expr:gte(t,n_forced*2)",
    "-c:a aac",
    "-b:a 192k",
    "-ar 48000",
    "-ac 2",
    "-f hls",
    "-hls_time 6",
    "-hls_playlist_type vod",
    "-hls_list_size 0",
    "-hls_segment_type mpegts",
    "-hls_flags single_file+independent_segments",
    "-master_pl_name index.m3u8",
    "-var_stream_map",
    [
      "v:0,agroup:audio,name:480p",
      "v:1,agroup:audio,name:720p",
      "v:2,agroup:audio,name:1080p",
      "v:3,agroup:audio,name:1440p",
      "v:4,agroup:audio,name:2160p",
      "a:0,agroup:audio,name:audio,default:yes"
    ].join(" "),
    "-hls_segment_filename hls_build/hls/%v.ts",
    "hls_build/hls/%v.m3u8"
  ].join(" ")

  puts JSON.dump({
    msg: "Running FFmpeg",
    full_command: ffmpeg_cmd
  })

  raise StandardError, "FFmpeg failed" unless system ffmpeg_cmd

  ["480", "720", "1080", "1440", "2160"].each do |size|
    send_to_s3("#{size}.ts")
    send_to_s3("#{size}.m3u8")
  end

  send_to_s3("index.m3u8")

  end_time = Time.now.to_i
  duration = end_time - start_time

  now = Time.now
  task_result["Time"] = now.getutc.iso8601
  task_result["Timestamp"] = now.to_i

  puts JSON.dump({msg: "Task output", output: task_result})
  sf.send_task_success({
    task_token: ENV["STATE_MACHINE_TASK_TOKEN"],
    output: task_result.to_json
  })

  send_end_metric(duration)
  puts JSON.dump({msg: "Task complete; success has been reported to state machine"})
rescue => e
  puts JSON.dump({msg: "Task failed!", error: e.class.name, cause: e.message})
  puts e.backtrace
  # p ff_stderr
  # p probe_stderr

  sf.send_task_failure({
    task_token: ENV["STATE_MACHINE_TASK_TOKEN"],
    error: e.class.name
    # cause: [e.message, ff_stderr, probe_stderr].compact.join("\n\n") TODO
  })
end
