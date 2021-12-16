# frozen_string_literal: true

require 'test_helper'
require 'json'

describe :porter do
  describe :ingesterror do
    it 'correctly handles an ingest error' do
      job = {
        Job: {
          Id: 'porter-test-ingest-error',
          Source: {
            Mode: 'HTTP',
            URL: 'http://example.com/404'
          }
        }
      }

      job_test(job) do |output|
        _(output['JobResult']['Job']['Id']).must_equal 'porter-test-ingest-error'
        _(output['JobResult']['State']).must_equal 'SOURCE_FILE_INGEST_ERROR'
        _(output['JobResult']['FailedTasks']).must_equal []

        _(output['JobResult']['TaskResults']).must_equal []
      end
    end
  end
end
