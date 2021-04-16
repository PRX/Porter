# frozen_string_literal: true

require 'test_helper'
require 'aws-sdk-states'
require 'json'

step_functions = Aws::States::Client.new(
  region: ENV['AWS_REGION']
)

describe :porter do
  describe :transcode do
    it 'returns execution output for a transcode task' do
      req = step_functions.start_execution({
                                            state_machine_arn: CONFIG.PORTER_STATE_MACHINE_ARN,
                                            input: {
                                              Job: {
                                                Id: 'porter-test-transcode',
                                                Source: {
                                                  Mode: 'HTTP',
                                                  URL: 'https://dovetail.prxu.org/152/245d0fe2-4171-4ebf-bea3-69deff3e9336/short.mp3'
                                                },
                                                Tasks: [
                                                  {
                                                    'Type': 'Transcode',
                                                    'Format': 'flac',
                                                    'Destination': {
                                                      'Mode': 'AWS/S3',
                                                      'BucketName': CONFIG.PORTER_TEST_BUCKET_NAME,
                                                      'ObjectKey': 'test/transcode-options/transcode.flac',
                                                      'Parameters': {
                                                        'CacheControl': 'max-age=604800',
                                                        'ContentDisposition': 'attachment; filename=\'download.flac\'',
                                                        'ContentType': 'audio/flac'
                                                      }
                                                    },
                                                    'FFmpeg': {
                                                      'InputFileOptions': '-t 1',
                                                      'OutputFileOptions': '-metadata title=some_title'
                                                    }
                                                  }
                                                ]
                                              }
                                            }.to_json
                                          })

      max_retries = 80
      retries = 0

      begin
        desc = step_functions.describe_execution({
                                                  execution_arn: req.execution_arn
                                                })

        raise RuntimeError if desc.status == 'RUNNING'
      rescue RuntimeError => e
        if retries <= max_retries
          retries += 1
          sleep 5
          retry
        else
          raise "Timeout: #{e.message}"
        end
      end

      output = JSON.parse(desc.output)

      _(output['JobResult']['Job']['Id']).must_equal 'porter-test-transcode'
      _(output['JobResult']['State']).must_equal 'DONE'
      _(output['JobResult']['FailedTasks']).must_equal []
      _(output['JobResult']['TaskResults'].length).must_equal 1
      _(output['JobResult']['TaskResults'][0]['Duration']).must_equal 1000
    end
  end
end
