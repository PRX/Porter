#!/usr/bin/ruby
# frozen_string_literal: true

# The following environment variables are passed in as ContainerOverrides when
# the state machine runs the ECS task
# STATE_MACHINE_NAME
# STATE_MACHINE_EXECUTION_ID
# STATE_MACHINE_JOB_ID
# STATE_MACHINE_TASK_INDEX
# STATE_MACHINE_AWS_REGION
# STATE_MACHINE_ARTIFACT_BUCKET_NAME
# STATE_MACHINE_ARTIFACT_OBJECT_KEY
# STATE_MACHINE_TASK_JSON

$stdout.sync = true
$stderr.sync = true

require 'rubygems'
require 'bundler/setup'
require 'aws-sdk-cloudwatch'
require 'net/sftp'
require 'net/ftp'
require 'logger'

load './ftp_files.rb'
load './s3_files.rb'
load './recorder.rb'

logger = Logger.new($stdout)
logger.debug('ftp.rb start')

start_time = Time.now
logger.debug("start_time: #{start_time}")

# Count the transfers in CloudWatch Metrics
recorder =
  Recorder.new(
    Aws::CloudWatch::Client.new,
    'PRX/Porter',
    [{ name: 'StateMachineName', value: ENV['STATE_MACHINE_NAME'] }]
  )

recorder.record('FtpTransfers', 'Count', 1.0)

bucket = ENV['STATE_MACHINE_ARTIFACT_BUCKET_NAME']
key = ENV['STATE_MACHINE_ARTIFACT_OBJECT_KEY']
logger.debug("Downloading artifact: '#{bucket}/#{key}'")
s3_files = S3Files.new(Aws::S3::Client.new, logger)
file = s3_files.download_file(bucket, key)

logger.debug("Transferring artifact: '#{bucket}/#{key}'")
ip = ENV['PUBLIC_IP']
task = JSON.parse(ENV['STATE_MACHINE_TASK_JSON'])
uri = URI.parse(task['URL'])
md5 = task['MD5'].nil? ? false : task['MD5']
passive = task['Passive'].nil? ? true : task['Passive']

ftp_files = FtpFiles.new(logger, recorder)
ftp_files.upload_file(uri, file, md5: md5, public_ip: ip, passive: passive)

# Count the transfers in CloudWatch Metrics
end_time = Time.now
duration = start_time - end_time

recorder.record('FtpTransferDuration', 'Seconds', duration)
