# frozen_string_literal: true

require "test_helper"
require "json"

describe :porter do
  describe :tone do
    it "returns execution output for a detect tone task" do
      job = {
        Job: {
          Id: "porter-test-detect-tone",
          Source: {
            Mode: "HTTP",
            URL: "https://raw.githubusercontent.com/PRX/Porter/master/test/samples/two-tone.flac"
          },
          Tasks: [
            {
              Type: "DetectTone",
              Frequency: 12
            },
            {
              Type: "DetectTone",
              Frequency: 1234
            }
          ]
        }
      }

      job_test(job) do |output|
        _(output["JobResult"]["Job"]["Id"]).must_equal "porter-test-detect-tone"
        _(output["JobResult"]["State"]).must_equal "DONE"
        _(output["JobResult"]["FailedTasks"]).must_equal []
        _(output["JobResult"]["TaskResults"].length).must_equal 2

        task_results = output["JobResult"]["TaskResults"]

        # Low frequency tone starts at 00:03 and is 1 second
        lf_task = task_results.find { |r| r["Tone"]["Frequency"] == 12 }
        lf_range = lf_task["Tone"]["Ranges"][0]
        _(lf_range["Start"]).must_be_close_to 3, 0.1
        _(lf_range["End"]).must_be_close_to 4, 0.1

        # High frequency tone starts at 00:01 and is 1 second
        hf_task = task_results.find { |r| r["Tone"]["Frequency"] == 1234 }
        hf_range = hf_task["Tone"]["Ranges"][0]
        _(hf_range["Start"]).must_be_close_to 1, 0.1
        _(hf_range["End"]).must_be_close_to 2, 0.1
      end
    end
  end
end
