# frozen_string_literal: true

require "minitest/reporters"
require "minitest/autorun"
require "minitest/spec"
require "minitest/pride"
require "minitest/focus"
require "config"
begin
  require "pry"
rescue
  LoadError
end
# output format
Minitest::Reporters.use! Minitest::Reporters::SpecReporter.new

MAX_RETRIES = 60
DEFAULT_TIMEOUT = 3

def job_test(job, timeout = DEFAULT_TIMEOUT)
  params = {
    state_machine_arn: CONFIG.PORTER_STATE_MACHINE_ARN,
    input: job.to_json
  }

  retries = 0
  task_req = STATES_CLIENT.start_execution(params)

  # Request task execution info; keep trying until it's ready
  begin
    params = {execution_arn: task_req.execution_arn}
    task_desc = STATES_CLIENT.describe_execution(params)

    raise RuntimeError if task_desc.status == "RUNNING"
  rescue RuntimeError => e
    if retries <= MAX_RETRIES
      retries += 1
      sleep timeout
      retry
    else
      raise "Timeout: #{e.message}"
    end
  end

  task_output = JSON.parse(task_desc.output)

  yield task_output
end
