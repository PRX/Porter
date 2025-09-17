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
# STATE_MACHINE_TASK_JSON
# STATE_MACHINE_ARTIFACT_JSON

# Raising an error will cause the Fargate container to exit, resulting in a
# States.TaskFailed error in the Step Function state. These will follow the
# state machine retry logic and/or send a task error callback

require "aws-sdk-cloudwatch"
require "aws-sdk-s3"
require "aws-sdk-sts"

require "json"

class String
  def underscore
    gsub("::", "/")
      .gsub(/([A-Z]+)([A-Z][a-z])/, '\1_\2')
      .gsub(/([a-z\d])([A-Z])/, '\1_\2')
      .tr("-", "_")
      .downcase
  end
end

artifact = JSON.parse(ENV["STATE_MACHINE_ARTIFACT_JSON"])

cloudwatch = Aws::CloudWatch::Client.new
get_artifact_s3tm = TransferManager.new

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
get_artifact_s3tm.download_file("artifact.file", bucket: ENV["STATE_MACHINE_ARTIFACT_BUCKET_NAME"], key: ENV["STATE_MACHINE_ARTIFACT_OBJECT_KEY"])

if ENV["STATE_MACHINE_DESTINATION_FORMAT"] == "INHERIT" && !artifact.dig("Descriptor", "Extension")
  raise StandardError, "Output format could not be inheritted"
end

# Execute the transcode
global_opts = ENV["STATE_MACHINE_FFMPEG_GLOBAL_OPTIONS"]
input_opts = ENV["STATE_MACHINE_FFMPEG_INPUT_FILE_OPTIONS"]
output_opts = ENV["STATE_MACHINE_FFMPEG_OUTPUT_FILE_OPTIONS"]
output_format = (ENV["STATE_MACHINE_DESTINATION_FORMAT"] == "INHERIT") ? artifact["Descriptor"]["Extension"] : ENV["STATE_MACHINE_DESTINATION_FORMAT"]
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

put_probe_s3_client = Aws::S3::Client.new(region: ENV["STATE_MACHINE_AWS_REGION"])
put_probe_s3tm = TransferManager.new(client: put_probe_s3_client)
bucket_name = ENV["STATE_MACHINE_ARTIFACT_BUCKET_NAME"]
object_key = "#{ENV["STATE_MACHINE_EXECUTION_ID"]}/transcode/ffprobe-#{ENV["STATE_MACHINE_TASK_INDEX"]}.json"
put_probe_s3tm.upload_file("ffprobe.json", bucket: bucket_name, object: object_key)

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

  credentials = Aws::Credentials.new(
    role.credentials.access_key_id,
    role.credentials.secret_access_key,
    role.credentials.session_token
  )

  # The Ruby AWS SDK does not intelligently handle cases where the client isn't
  # explicitly set for the region where the bucket exists. We have to detect
  # the region using HeadBucket, and then create the client with the returned
  # region.
  # TODO This isn't necessary when the bucket and the client are in the same
  # region. It would be possible to catch the error and do the lookup only when
  # necessary.

  # Create a client with permission to HeadBucket
  begin
    s3_writer = Aws::S3::Client.new(credentials: credentials, endpoint: "https://s3.amazonaws.com")
    bucket_head = s3_writer.head_bucket({bucket: ENV["STATE_MACHINE_DESTINATION_BUCKET_NAME"]})
    bucket_region = bucket_head.context.http_response.headers["x-amz-bucket-region"]
  rescue Aws::S3::Errors::Http301Error, Aws::S3::Errors::PermanentRedirect => e
    bucket_region = e.context.http_response.headers["x-amz-bucket-region"]
  end

  puts "Destination bucket in region: #{bucket_region}"

  # Create a new client with the permissions and the correct region
  s3_writer = Aws::S3::Client.new(credentials: credentials, region: bucket_region)

  put_object_params = {}

  # When the optional `ContentType` property is set to `REPLACE`, if a MIME is
  # included with the artifact, that should be used as the new file's
  # content type
  if destination["ContentType"] == "REPLACE" && artifact.dig("Descriptor", "MIME")
    put_object_params[:content_type] = artifact["Descriptor"]["MIME"]
  end

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

  put_object_params[:bucket] = ENV["STATE_MACHINE_DESTINATION_BUCKET_NAME"]
  put_object_params[:key] = ENV["STATE_MACHINE_DESTINATION_OBJECT_KEY"]

  # Upload the encoded file to the S3
  puts "Writing output to S3 destination"
  put_ouput_s3tm = TransferManager.new(client: s3_writer)
  put_ouput_s3tm.upload_file("output.file", **put_object_params)
end
