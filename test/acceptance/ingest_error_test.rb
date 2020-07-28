require 'test_helper'
require 'aws-sdk-states'
require 'json'

step_functions = Aws::States::Client.new(
  region: 'us-east-1'
)

describe :porter do
  describe :ingesterror do
    it 'correctly handles an ingest error' do
      req = step_functions.start_execution({
        state_machine_arn: CONFIG.PORTER_STATE_MACHINE_ARN,
        input: {
          Job: {
            Id: 'porter-test-ingest-error',
            Source: {
              Mode: 'HTTP',
              URL: 'http://example.com/404'
            }
          }
        }.to_json
      })

      max_retries = 60
      retries = 0

      begin
        desc = step_functions.describe_execution({
          execution_arn: req.execution_arn,
        })

        raise RuntimeError if desc.status == 'RUNNING'
      rescue RuntimeError => e
        if retries <= max_retries
          retries += 1
          sleep 2
          retry
        else
          raise "Timeout: #{e.message}"
        end
      end

      output = JSON.parse(desc.output)

      _(output['JobResult']['Job']['Id']).must_equal 'porter-test-ingest-error'
      _(output['JobResult']['State']).must_equal 'SOURCE_FILE_INGEST_ERROR'
      _(output['JobResult']['FailedTasks']).must_equal []
      _(output['JobResult']['TaskResults']).must_equal []
    end
  end
end
