# frozen_string_literal: true

require "test_helper"
require "json"

describe :porter do
  parallelize_me!

  describe :noop do
    it "returns the basic execution output2" do
      job = {
        Job: {
          Id: "porter-test-no-op",
          Source: {
            Mode: "HTTP",
            URL: "http://example.com/"
          }
        }
      }

      job_test(job) do |output|
        _(output["JobResult"]["Job"]["Id"]).must_equal "porter-test-no-op"
        _(output["JobResult"]["State"]).must_equal "DONE"
        _(output["JobResult"]["FailedTasks"]).must_equal []
        _(output["JobResult"]["TaskResults"]).must_equal []
      end
    end
  end
end
