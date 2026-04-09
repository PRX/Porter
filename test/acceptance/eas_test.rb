# frozen_string_literal: true

require "test_helper"
require "json"

describe :porter do
  parallelize_me!

  describe :eas do
    it "returns execution output for a detect eas task" do
      job = {
        Job: {
          Id: "porter-test-detect-eas",
          Source: {
            Mode: "HTTP",
            URL: "https://raw.githubusercontent.com/PRX/Porter/master/test/samples/eas-eom-only.wav"
          },
          Tasks: [
            {
              Type: "DetectEas"
            }
          ]
        }
      }

      job_test(job) do |output|
        _(output["JobResult"]["Job"]["Id"]).must_equal "porter-test-detect-eas"
        _(output["JobResult"]["State"]).must_equal "DONE"
        _(output["JobResult"]["FailedTasks"]).must_equal []
        _(output["JobResult"]["TaskResults"].length).must_equal 1

        result = output["JobResult"]["TaskResults"][0]["EAS"]
        _(result["easDetected"]).must_equal true
        _(result["matchType"]).must_equal "partial"
        _(result["timecodes"][0]["start"]).must_be_close_to 0.541, 0.1
        _(result["timecodes"][0]["end"]).must_be_close_to 0.802, 0.1
      end
    end

    it "returns execution output for a sensitive detect eas task" do
      job = {
        Job: {
          Id: "porter-test-detect-eas",
          Source: {
            Mode: "HTTP",
            URL: "https://raw.githubusercontent.com/PRX/Porter/master/test/samples/eas-eom-only.wav"
          },
          Tasks: [
            {
              Type: "DetectEas",
              FSKMode: "Sensitve"
            }
          ]
        }
      }

      job_test(job) do |output|
        _(output["JobResult"]["Job"]["Id"]).must_equal "porter-test-detect-eas"
        _(output["JobResult"]["State"]).must_equal "DONE"
        _(output["JobResult"]["FailedTasks"]).must_equal []
        _(output["JobResult"]["TaskResults"].length).must_equal 1
        _(output["JobResult"]["TaskResults"][0]["FSKMode"]).must_equal "Sensitive"

        result = output["JobResult"]["TaskResults"][0]["EAS"]
        _(result["matchType"]).must_equal "partial"
        _(result["timecodes"][0]["start"]).must_be_close_to 0.541, 0.1
        _(result["timecodes"][0]["end"]).must_be_close_to 0.802, 0.1
      end
    end
  end
end
