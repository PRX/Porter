# frozen_string_literal: true

require 'test_helper'
require 'json'

describe :porter do
  describe :transcribe do
    it 'fails with invalid media format' do
      job = {
        Job: {
          Id: 'porter-test-transcribe-invalid-media-format',
          Source: {
            Mode: 'HTTP',
            URL: 'https://dovetail.prxu.org/152/245d0fe2-4171-4ebf-bea3-69deff3e9336/short.mp3'
          },
          Tasks: [
            {
              Type: 'Transcribe',
              LanguageCode: 'en-US',
              MediaFormat: 'divx',
              Destination: {
                Mode: 'AWS/S3',
                BucketName: CONFIG.PORTER_TEST_BUCKET_NAME,
                ObjectKey: 'test/transcribe-invalid-media-format/transcript.json'
              }
            }
          ]
        }
      }

      job_test(job, 5) do |output|
        _(output['JobResult']['Job']['Id']).must_equal 'porter-test-transcribe-invalid-media-format'
        _(output['JobResult']['State']).must_equal 'DONE'
        _(output['JobResult']['TaskResults']).must_equal []
        _(output['JobResult']['FailedTasks'].length).must_equal 1
      end
    end
  end
end
