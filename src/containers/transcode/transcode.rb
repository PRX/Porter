#!/usr/bin/env ruby
require 'bundler/inline'
require 'json'

gemfile do
  source 'https://rubygems.org'
  gem 'aws-sdk-cloudwatch', '~> 1'
  gem 'aws-sdk-s3', '~> 1'
  gem 'aws-sdk-sts', '~> 1'
end

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
# STATE_MACHINE_DESTINATION_MODE
# STATE_MACHINE_DESTINATION_FORMAT
# STATE_MACHINE_DESTINATION_JSON
# STATE_MACHINE_FFMPEG_GLOBAL_OPTIONS
# STATE_MACHINE_FFMPEG_INPUT_FILE_OPTIONS
# STATE_MACHINE_FFMPEG_OUTPUT_FILE_OPTIONS

cloudwatch = Aws::CloudWatch::Client.new
s3 = Aws::S3::Client.new

start_time = Time.now.to_i

cloudwatch.put_metric_data({
  namespace: 'PRX/Porter',
  metric_data: [
    {
        metric_name: 'Transcodes',
        dimensions: [
          {
                name: 'StateMachineName',
                value: ENV['STATE_MACHINE_NAME']
            }
        ],
        value: 1,
        unit: 'Count'
    }
  ]
})

puts 'Downloading artifact'
File.open('artifact.file', 'wb') do |file|
  s3.get_object({ bucket: ENV['STATE_MACHINE_ARTIFACT_BUCKET_NAME'], key: ENV['STATE_MACHINE_ARTIFACT_OBJECT_KEY'] }, target: file)
end

# Execute the transcode
ffmpeg_cmd = [
  './ffmpeg-bin/ffmpeg',
  ENV['STATE_MACHINE_FFMPEG_GLOBAL_OPTIONS'],
  "#{ENV['STATE_MACHINE_FFMPEG_INPUT_FILE_OPTIONS']} -i artifact.file",
  "#{ENV['STATE_MACHINE_FFMPEG_OUTPUT_FILE_OPTIONS']} -f #{ENV['STATE_MACHINE_DESTINATION_FORMAT']} output.file"
].join(' ')

puts 'Calling FFmpeg'
puts ffmpeg_cmd

raise StandardError, 'FFmpeg failed' unless system ffmpeg_cmd

end_time = Time.now.to_i
duration = end_time - start_time

# Probe the output of the transcode
ffprobe_cmd = [
  './ffmpeg-bin/ffprobe',
  '-v error',
  '-show_streams',
  '-show_format',
  '-i output.file',
  '-print_format json',
  '> ffprobe.json'
].join(' ')

raise StandardError, 'FFmpeg probe failed' unless system ffprobe_cmd

# Write the probe output to S3
puts 'Writing probe output to S3 artifact bucket'
s3 = Aws::S3::Resource.new(region: ENV['STATE_MACHINE_AWS_REGION'])
key = "#{ENV['STATE_MACHINE_EXECUTION_ID']}/transcode/ffprobe-#{ENV['STATE_MACHINE_TASK_INDEX']}.json"
obj = s3.bucket(ENV['STATE_MACHINE_ARTIFACT_BUCKET_NAME']).object('key')
obj.upload_file('ffprobe.json')

# Record transcode duration in CloudWatch Metrics
cloudwatch.put_metric_data({
  namespace: 'PRX/Porter',
  metric_data: [
    {
        metric_name: 'TranscodeDuration',
        dimensions: [
          {
                name: 'StateMachineName',
                value: ENV['STATE_MACHINE_NAME']
            }
        ],
        value: duration,
        unit: 'Seconds'
    }
  ]
})

destination = JSON.parse(ENV['STATE_MACHINE_DESTINATION_JSON'])

if destination['Mode'] == 'AWS/S3'
  region = ENV['STATE_MACHINE_AWS_REGION']

  sts = Aws::STS::Client.new(endpoint: "https://sts.#{region}.amazonaws.com")

  # Assume a role that will have access to the S3 destination bucket, and use
  # that roles credentials for the S3 upload
  role = sts.assume_role({
    role_arn: ENV['STATE_MACHINE_S3_DESTINATION_WRITER_ROLE'],
    role_session_name: 'porter_transcode_task'
  })
end

# TODO: Convert to Ruby
# s3_writer = boto3.resource(
#     's3',
#     aws_access_key_id=role['Credentials']['AccessKeyId'],
#     aws_secret_access_key=role['Credentials']['SecretAccessKey'],
#     aws_session_token=role['Credentials']['SessionToken'],
# )

#   = {}

# if 'Parameters' in destination:
#     s3_parameters = destination['Parameters']

# # Upload the encoded file to the S3
# print('Writing output to S3 destination')
# s3_writer.meta.client.upload_file(
#     'output.file',
#     os.environ['STATE_MACHINE_DESTINATION_BUCKET_NAME'],
#     os.environ['STATE_MACHINE_DESTINATION_OBJECT_KEY'],
#     ExtraArgs=s3_parameters
# )
