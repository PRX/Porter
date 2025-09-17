# frozen_string_literal: true

require "test_helper"
require "json"

describe :porter do
  parallelize_me!

  describe :wavwrap do
    it "returns execution output for a wav-wrap task" do
      job = {
        Job: {
          Id: "porter-test-wav-wrap",
          Source: {
            Mode: "HTTP",
            URL: "https://raw.githubusercontent.com/PRX/Porter/master/test/samples/two-tone.mp2"
          },
          Tasks: [
            {
              Type: "WavWrap",
              Destination: {
                Mode: "AWS/S3",
                BucketName: CONFIG.PORTER_TEST_BUCKET_NAME,
                ObjectKey: "test/wav-wrap/two-tone.wav",
                ContentType: "audio/wav",
                Parameters: {
                  ContentDisposition: "attachment",
                  Metadata: {
                    MyMetadataKey: "MyMetadataValue"
                  }
                }
              },
              Chunks: [
                {
                  ChunkId: "cart",
                  CutId: "30000",
                  Title: "SOUNDOPI: 20191129: 731: 06: Thanksgiving Leftovers & DJ Shadow on Sampling",
                  Artist: "Sound Opinions",
                  StartDate: "2020/05/31",
                  StartTime: "10:00:00",
                  EndDate: "2020/06/10",
                  EndTime: "10:00:00",
                  ProducerAppId: "PRX",
                  ProducerAppVersion: "3.0"
                }
              ]
            }
          ]
        }
      }

      job_test(job) do |output|
        _(output["JobResult"]["Job"]["Id"]).must_equal "porter-test-wav-wrap"
        _(output["JobResult"]["State"]).must_equal "DONE"
        _(output["JobResult"]["FailedTasks"]).must_equal []
        _(output["JobResult"]["TaskResults"].length).must_equal 1
      end
    end
  end
end
