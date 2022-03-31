# frozen_string_literal: true

require 'test_helper'
require 'json'

describe :porter do
  describe :silence do
    it 'returns execution output for an detect silence task' do
      job = {
        Job: {
          Id: 'porter-test-detect-silence',
          Source: {
            Mode: 'HTTP',
            URL: 'https://raw.githubusercontent.com/PRX/Porter/master/test/samples/silence.flac'
          },
          Tasks: [
            {
              Type: 'DetectSilence'
            }
          ]
        }
      }

      job_test(job) do |output|
        _(output['JobResult']['Job']['Id']).must_equal 'porter-test-detect-silence'
        _(output['JobResult']['State']).must_equal 'DONE'
        _(output['JobResult']['FailedTasks']).must_equal []
        _(output['JobResult']['TaskResults'].length).must_equal 1

        range = output['JobResult']['TaskResults'][0]['Silence']['Ranges'][0]
        _(range['Start']).must_be_close_to 2, 0.01
        _(range['End']).must_be_close_to 3, 0.01
      end
    end
  end
end
