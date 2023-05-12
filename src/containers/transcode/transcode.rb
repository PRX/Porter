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
# STATE_MACHINE_DESTINATION_OBJECT_KEY
# STATE_MACHINE_DESTINATION_FORMAT
# STATE_MACHINE_FFMPEG_GLOBAL_OPTIONS
# STATE_MACHINE_FFMPEG_INPUT_FILE_OPTIONS
# STATE_MACHINE_FFMPEG_OUTPUT_FILE_OPTIONS

require "aws-sdk-cloudwatch"
require "aws-sdk-s3"
require "aws-sdk-sts"

require "json"

class String
  def underscore
    gsub(/::/, "/")
      .gsub(/([A-Z]+)([A-Z][a-z])/, '\1_\2')
      .gsub(/([a-z\d])([A-Z])/, '\1_\2')
      .tr("-", "_")
      .downcase
  end
end

cloudwatch = Aws::CloudWatch::Client.new
s3 = Aws::S3::Client.new

start_time = Time.now.to_i

# Count the transcode in CloudWatch Metrics
cloudwatch.put_metric_data({
  namespace: "PRX/Porter",
  metric_data: [
    {
      metric_name: "Transcodes",
      dimensions: [
        {
          name: "StateMachineName",
          value: ENV["STATE_MACHINE_NAME"]
        }
      ],
      value: 1,
      unit: "Count"
    }
  ]
})

# Get the artifact file from S3
puts "Downloading artifact"
File.open("artifact.file", "wb") do |file|
  s3.get_object(
    {
      bucket: ENV["STATE_MACHINE_ARTIFACT_BUCKET_NAME"],
      key: ENV["STATE_MACHINE_ARTIFACT_OBJECT_KEY"]
    },
    target: file
  )
end

# Execute the transcode
global_opts = ENV["STATE_MACHINE_FFMPEG_GLOBAL_OPTIONS"]
input_opts = ENV["STATE_MACHINE_FFMPEG_INPUT_FILE_OPTIONS"]
output_opts = ENV["STATE_MACHINE_FFMPEG_OUTPUT_FILE_OPTIONS"]
output_format = ENV["STATE_MACHINE_DESTINATION_FORMAT"]
ffmpeg_cmd = [
  "./ffmpeg-bin/ffmpeg",
  global_opts,
  "#{input_opts} -i artifact.file",
  "#{output_opts} -f #{output_format} output.file"
].join(" ")

puts "Calling FFmpeg"
puts ffmpeg_cmd

raise StandardError, "FFmpeg failed" unless system ffmpeg_cmd

end_time = Time.now.to_i
duration = end_time - start_time

# Probe the output of the transcode
ffprobe_cmd = [
  "./ffmpeg-bin/ffprobe",
  "-v error",
  "-show_streams",
  "-show_format",
  "-i output.file",
  "-print_format json",
  "> ffprobe.json"
].join(" ")

raise StandardError, "FFmpeg probe failed" unless system ffprobe_cmd

# Write the probe output to S3
puts "Writing probe output to S3 artifact bucket"
s3 = Aws::S3::Resource.new(region: ENV["STATE_MACHINE_AWS_REGION"])
bucket_name = ENV["STATE_MACHINE_ARTIFACT_BUCKET_NAME"]
object_key = "#{ENV["STATE_MACHINE_EXECUTION_ID"]}/transcode/ffprobe-#{ENV["STATE_MACHINE_TASK_INDEX"]}.json"
obj = s3.bucket(bucket_name).object(object_key)
obj.upload_file("ffprobe.json")

# Record transcode duration in CloudWatch Metrics
cloudwatch.put_metric_data({
  namespace: "PRX/Porter",
  metric_data: [
    {
      metric_name: "TranscodeDuration",
      dimensions: [
        {
          name: "StateMachineName",
          value: ENV["STATE_MACHINE_NAME"]
        }
      ],
      value: duration,
      unit: "Seconds"
    }
  ]
})

destination = JSON.parse(ENV["STATE_MACHINE_DESTINATION_JSON"])

if destination["Mode"] == "AWS/S3"
  region = ENV["STATE_MACHINE_AWS_REGION"]

  sts = Aws::STS::Client.new(endpoint: "https://sts.#{region}.amazonaws.com")

  # Assume a role that will have access to the S3 destination bucket, and use
  # that role's credentials for the S3 upload
  role = sts.assume_role({
    role_arn: ENV["STATE_MACHINE_S3_DESTINATION_WRITER_ROLE"],
    role_session_name: "porter_transcode_task"
  })

  s3_writer = Aws::S3::Client.new(credentials: role)

  put_object_params = {}

  # For historical reasons, the available parameters match ALLOWED_UPLOAD_ARGS
  # from Boto3's S3Transfer class.
  # https://boto3.amazonaws.com/v1/documentation/api/latest/reference/customizations/s3.html
  # If any parameters are included on the destination config, they are
  # reformatted to snake case, and added to the put_object params as symbols.
  if destination.key?("Parameters")
    destination["Parameters"].each do |k, v|
      put_object_params[k.underscore.to_sym] = v
    end
  end

  # Upload the encoded file to the S3
  puts "Writing output to S3 destination"
  File.open("output.file", "rb") do |file|
    put_object_params[:bucket] = ENV["STATE_MACHINE_DESTINATION_BUCKET_NAME"]
    put_object_params[:key] = ENV["STATE_MACHINE_DESTINATION_OBJECT_KEY"]
    put_object_params[:body] = file

    s3_writer.put_object(put_object_params)
  end
end