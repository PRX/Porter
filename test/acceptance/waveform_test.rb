# frozen_string_literal: true

require 'test_helper'
require 'json'

describe :porter do
  describe :waveform do
    it 'returns execution output for a binary waveform task' do
      job = {
        Job: {
          Id: 'porter-test-waveform-binary',
          Source: {
            Mode: 'HTTP',
            URL: 'https://raw.githubusercontent.com/PRX/Porter/master/test/samples/two-tone.flac'
          },
          Tasks: [
            {
              Type: 'Waveform'
              Generator: 'BBC/audiowaveform/v1.x',
              DataFormat: 'Binary',
              Destination: {
                Mode: 'AWS/S3',
                BucketName: 'prx-porter-sandbox',
                ObjectKey: 'dev/sample/waveform/waveform.dat'
              }
            }
          ]
        }
      }

      job_test(job) do |output|
        _(output['JobResult']['Job']['Id']).must_equal 'porter-test-waveform-binary'
        _(output['JobResult']['State']).must_equal 'DONE'
        _(output['JobResult']['FailedTasks']).must_equal []
        _(output['JobResult']['TaskResults'].length).must_equal 1
      end
    end

    it 'returns execution output for a JSON waveform task' do
      job = {
        Job: {
          Id: 'porter-test-waveform-json',
          Source: {
            Mode: 'HTTP',
            URL: 'https://raw.githubusercontent.com/PRX/Porter/master/test/samples/two-tone.flac'
          },
          Tasks: [
            {
              Type: 'Waveform'
              Generator: 'BBC/audiowaveform/v1.x',
              DataFormat: 'JSON',
              Destination: {
                Mode: 'AWS/S3',
                BucketName: 'prx-porter-sandbox',
                ObjectKey: 'dev/sample/waveform/waveform.json'
              }
            }
          ]
        }
      }

      job_test(job) do |output|
        _(output['JobResult']['Job']['Id']).must_equal 'porter-test-waveform-json'
        _(output['JobResult']['State']).must_equal 'DONE'
        _(output['JobResult']['FailedTasks']).must_equal []
        _(output['JobResult']['TaskResults'].length).must_equal 1
      end
    end

    it 'returns execution output for a waveform task with options' do
      job = {
        Job: {
          Id: 'porter-test-waveform-options',
          Source: {
            Mode: 'HTTP',
            URL: 'https://raw.githubusercontent.com/PRX/Porter/master/test/samples/two-tone.flac'
          },
          Tasks: [
            {
              Type: 'Waveform'
              Generator: 'BBC/audiowaveform/v1.x',
              DataFormat: 'JSON',
              WaveformPointBitDepth: 8,
              WaveformPointFrequency: 256,
              Destination: {
                Mode: 'AWS/S3',
                BucketName: 'prx-porter-sandbox',
                ObjectKey: 'dev/sample/waveform/waveform.json'
              }
            }
          ]
        }
      }

      job_test(job) do |output|
        _(output['JobResult']['Job']['Id']).must_equal 'porter-test-waveform-options'
        _(output['JobResult']['State']).must_equal 'DONE'
        _(output['JobResult']['FailedTasks']).must_equal []
        _(output['JobResult']['TaskResults'].length).must_equal 1
      end
    end
  end
end
