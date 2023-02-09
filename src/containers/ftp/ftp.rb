#!/usr/bin/ruby
# frozen_string_literal: true

# The following environment variables are passed in as ContainerOverrides when
# the state machine runs the ECS task
# STATE_MACHINE_ARN
# STATE_MACHINE_NAME
# STATE_MACHINE_EXECUTION_ID
# STATE_MACHINE_JOB_ID
# STATE_MACHINE_TASK_INDEX
# STATE_MACHINE_AWS_REGION
# STATE_MACHINE_ARTIFACT_BUCKET_NAME
# STATE_MACHINE_ARTIFACT_OBJECT_KEY
# STATE_MACHINE_TASK_JSON
# Set elsewhere
# FTP_LISTEN_PORT
# PUBLIC_IP

$stdout.sync = true
$stderr.sync = true

require 'rubygems'
require 'bundler/setup'
require 'aws-sdk-cloudwatch'
require 'net/sftp'
require 'net/ftp'
require 'logger'

load './ftp_files.rb'
load './sftp_files.rb'
load './s3_files.rb'
load './recorder.rb'

RESULT_KEY = "#{ENV['STATE_MACHINE_EXECUTION_ID']}/copy/ftp-result-#{ENV['STATE_MACHINE_TASK_INDEX']}.json"

logger = Logger.new($stdout)
start_time = Time.now

logger.debug(JSON.dump({
  msg: 'ftp.rb start',
  start_time: start_time
}))

begin
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
  logger.debug(JSON.dump({
    msg: 'Copying artifact to container',
    bucket_name: bucket,
    object_key: key
  }))
  s3 = Aws::S3::Client.new
  s3_files = S3Files.new(s3, logger)
  file = s3_files.download_file(bucket, key)

  public_ip = ENV['PUBLIC_IP']
  public_port = ENV['FTP_LISTEN_PORT']
  task = JSON.parse(ENV['STATE_MACHINE_TASK_JSON'])
  uri = URI.parse(task['URL'])
  md5 = task['MD5'].nil? ? false : task['MD5']
  timeout = task['Timeout'].nil? ? 1800 : task['Timeout']
  # This value is not guaranteed to be honored, so it's undocumented
  max_attempts = task['MaxAttempts'].nil? ? 6 : task['MaxAttempts']

  if uri.scheme == 'ftp' || uri.scheme == 'ftps'
    ftp_files = FtpFiles.new(logger, recorder)
    ftp_options = {
      md5: md5,
      public_ip: public_ip,
      public_port: public_port,
      mode: task['Mode'],
      timeout: timeout,
      max_attempts: max_attempts,
      use_tls: uri.scheme == 'ftps'
    }
    used_mode = ftp_files.upload_file(uri, file, ftp_options)

    if used_mode
      logger.debug(JSON.dump({
        msg: 'Copying state machine results file',
        bucket_name: bucket,
        object_key: RESULT_KEY
      }))
      s3.put_object(
        bucket: bucket,
        key: RESULT_KEY,
        body: JSON.dump({
          # All properties listed here will be included in the task result for
          # this task.
          Mode: used_mode
        })
      )
    end
  elsif uri.scheme == 'sftp'
    sftp_files = SftpFiles.new(logger, recorder)
    sftp_files.upload_file(uri, file, md5: md5)

    logger.debug(JSON.dump({
      msg: 'Copying state machine results file',
      bucket_name: bucket,
      object_key: RESULT_KEY
    }))
    s3.put_object(
      bucket: bucket,
      key: RESULT_KEY,
      body: JSON.dump({
        # All properties listed here will be included in the task result for
        # this task.
        # Foo: "bar"
      })
    )
  end
rescue StandardError => e
  puts e.backtrace

  logger.debug(JSON.dump({
    msg: 'Copying state machine results file for error',
    bucket_name: bucket,
    object_key: RESULT_KEY
  }))
  s3.put_object(
    bucket: bucket,
    key: RESULT_KEY,
    body: JSON.dump({
      Error: e.class.name,
      ErrorMessage: e.message
    })
  )
end

# Count the transfers in CloudWatch Metrics
end_time = Time.now
duration = end_time - start_time

recorder.record('FtpTransferDuration', 'Seconds', duration)

logger.debug(JSON.dump({
  msg: 'ftp.rb end',
  duration: duration
}))
