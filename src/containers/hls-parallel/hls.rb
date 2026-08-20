#!/bin/ruby

# The following environment variables are passed in as ContainerOverrides when
# the state machine runs the ECS task
# - STATE_MACHINE_AWS_REGION
#
# - STATE_MACHINE_ARTIFACT_BUCKET_NAME
# - STATE_MACHINE_ARTIFACT_OBJECT_KEY
#
# - STATE_MACHINE_TASK_TOKEN
#
# - STATE_MACHINE_HLS_PRESET_LABEL
# - STATE_MACHINE_HLS_FILE_STEM
#
# - STATE_MACHINE_FFMPEG_COMMAND_PARTS_JSON
#
# - STATE_MACHINE_DESTINATION_JSON
# - STATE_MACHINE_S3_DESTINATION_WRITER_ROLE

require "json"
require "time"
require "open3"
require "aws-sdk-states"
require "aws-sdk-s3"
# load "./telemetry.rb"
load "./destinations/aws/s3.rb"

sf = Aws::States::Client.new
s3 = Aws::S3::Client.new

begin
  # This will be the output included in `send_task_success`, and become the
  # result of state
  task_output = {
    PresetLabel: ENV["STATE_MACHINE_HLS_PRESET_LABEL"]
  }

  puts JSON.dump({
    msg: "Getting object from S3…",
    bucket: ENV["STATE_MACHINE_ARTIFACT_BUCKET_NAME"],
    key: ENV["STATE_MACHINE_ARTIFACT_OBJECT_KEY"]
  })
  s3.get_object(
    bucket: ENV["STATE_MACHINE_ARTIFACT_BUCKET_NAME"],
    key: ENV["STATE_MACHINE_ARTIFACT_OBJECT_KEY"],
    response_target: "artifact.file"
  )

  ffmpeg_command_parts = JSON.parse(ENV["STATE_MACHINE_FFMPEG_COMMAND_PARTS_JSON"])

  puts JSON.dump({
    msg: "Executing FFmpeg command…",
    full_command: ffmpeg_command_parts.join(" ")
  })

  start_time = Time.now.to_i
  raise StandardError, "FFmpeg failed" unless system(*ffmpeg_command_parts)
  end_time = Time.now.to_i
  duration = end_time - start_time

  puts JSON.dump({msg: "FFmpeg command completed", duration: duration})

  file_stem = ENV["STATE_MACHINE_HLS_FILE_STEM"]

  m3u8_tx = send_to_s3("#{file_stem}.m3u8")
  media_tx = send_to_s3("#{file_stem}.ts")

  task_output[:M3U8] = File.read("#{file_stem}.m3u8")
  task_output[:Playlist] = {
    ObjectKey: m3u8_tx[:ObjectKey]
  }
  task_output[:Media] = {
    ObjectKey: media_tx[:ObjectKey]
  }

  sf.send_task_success({
    task_token: ENV["STATE_MACHINE_TASK_TOKEN"],
    output: task_output.to_json
  })

  puts JSON.dump({msg: "Done! Success has been reported to state machine"})
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
  puts JSON.dump({msg: "Failure has been reported to state machine"})
end
