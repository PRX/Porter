# frozen_string_literal: true

require "test_helper"
require "json"

describe :porter do
  describe :inspect do
    it "returns execution output for an inspect task" do
      job = {
        Job: {
          Id: "porter-test-inspect",
          Source: {
            Mode: "Data/URI",
            URI: "data:image/gif;base64,R0lGODlhAQABAIAAAAAAAP///yH5BAEAAAAALAAAAAABAAEAAAIBRAA7"
          },
          Tasks: [
            {
              Type: "Inspect"
            }
          ]
        }
      }

      job_test(job) do |output|
        _(output["JobResult"]["Job"]["Id"]).must_equal "porter-test-inspect"
        _(output["JobResult"]["State"]).must_equal "DONE"
        _(output["JobResult"]["FailedTasks"]).must_equal []
        _(output["JobResult"]["TaskResults"].length).must_equal 1
        _(output["JobResult"]["TaskResults"][0]["Inspection"]["Image"]["Format"]).must_equal "gif"
      end
    end
  end
end
