#!/usr/bin/ruby

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

STDOUT.sync = true
STDERR.sync = true

require 'logger'
require 'aws-sdk-cloudwatch'
require 'net/sftp'
require 'net/ftp'

load './ftp_files.rb'
load './s3_files.rb'

logger = Logger.new(STDOUT)
logger.debug('ftp.rb start')

start_time = Time.now
logger.debug("start_time: #{start_time}")

# Count the transfers in CloudWatch Metrics
cloudwatch = Aws::CloudWatch::Client.new
cloudwatch.put_metric_data(
  {
    namespace: 'PRX/Porter',
    metric_data: [
      {
        metric_name: 'FtpTransfers',
        dimensions: [
          { name: 'StateMachineName', value: ENV['STATE_MACHINE_NAME'] }
        ],
        value: 1.0,
        unit: 'Count'
      }
    ]
  }
)

bucket = ENV['STATE_MACHINE_ARTIFACT_BUCKET_NAME']
key = ENV['STATE_MACHINE_ARTIFACT_OBJECT_KEY']
logger.debug("Downloading artifact: '#{bucket}/#{key}'")
s3_files = S3Files.new(Aws::S3::Client.new, logger)
file = s3_files.download_file(bucket, key)

logger.debug("Transferring artifact: '#{bucket}/#{key}'")
ip = ENV['PUBLIC_IP']
task = JSON.parse(ENV['STATE_MACHINE_TASK_JSON'])
uri = URI.parse(task['URL'])
md5 = task['MD5'].nil? ? false : !!task['MD5']
passive = task['Passive'].nil? ? true : !!task['Passive']

ftp_files = FtpFiles.new(logger)
ftp_files.upload_file(uri, file, md5: md5, public_ip: ip, passive: passive)

# Count the transfers in CloudWatch Metrics
end_time = Time.now
duration = start_time - end_time
cloudwatch.put_metric_data(
  {
    namespace: 'PRX/Porter',
    metric_data: [
      {
        metric_name: 'FtpTransferDuration',
        dimensions: [
          { name: 'StateMachineName', value: ENV['STATE_MACHINE_NAME'] }
        ],
        value: duration,
        unit: 'Seconds'
      }
    ]
  }
)
