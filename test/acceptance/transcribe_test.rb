# frozen_string_literal: true

require "test_helper"
require "json"

describe :porter do
  parallelize_me!

  describe :transcribe do
    it "returns execution output for an transcribe task" do
      job = {
        Job: {
          Id: "porter-test-transcribe-output",
          Source: {
            Mode: "HTTP",
            URL: "https://dovetail.prxu.org/152/245d0fe2-4171-4ebf-bea3-69deff3e9336/short.mp3"
          },
          Tasks: [
            {
              Type: "Transcribe",
              LanguageCode: "en-US",
              SubtitleFormats: ["vtt"],
              Destination: {
                Mode: "AWS/S3",
                BucketName: CONFIG.PORTER_TEST_BUCKET_NAME,
                ObjectKey: "test/transcribe-output/transcript.json"
              }
            }
          ]
        }
      }

      job_test(job, 10) do |output|
        _(output["JobResult"]["Job"]["Id"]).must_equal "porter-test-transcribe-output"
        _(output["JobResult"]["State"]).must_equal "DONE"
        _(output["JobResult"]["FailedTasks"]).must_equal []
        _(output["JobResult"]["TaskResults"].length).must_equal 1
        _(output["JobResult"]["TaskResults"][0]["SubtitleFormats"][0]).must_equal "vtt"
      end
    end

    it "fails with invalid media format" do
      job = {
        Job: {
          Id: "porter-test-transcribe-invalid-media-format",
          Source: {
            Mode: "HTTP",
            URL: "https://dovetail.prxu.org/152/245d0fe2-4171-4ebf-bea3-69deff3e9336/short.mp3"
          },
          Tasks: [
            {
              Type: "Transcribe",
              LanguageCode: "en-US",
              MediaFormat: "divx",
              Destination: {
                Mode: "AWS/S3",
                BucketName: CONFIG.PORTER_TEST_BUCKET_NAME,
                ObjectKey: "test/transcribe-invalid-media-format/transcript.json"
              }
            }
          ]
        }
      }

      job_test(job) do |output|
        _(output["JobResult"]["Job"]["Id"]).must_equal "porter-test-transcribe-invalid-media-format"
        _(output["JobResult"]["State"]).must_equal "DONE"
        _(output["JobResult"]["TaskResults"]).must_equal []
        _(output["JobResult"]["FailedTasks"].length).must_equal 1
      end
    end

    it "fails with invalid subtitle format" do
      job = {
        Job: {
          Id: "porter-test-transcribe-invalid-subtitle-format",
          Source: {
            Mode: "HTTP",
            URL: "https://dovetail.prxu.org/152/245d0fe2-4171-4ebf-bea3-69deff3e9336/short.mp3"
          },
          Tasks: [
            {
              Type: "Transcribe",
              LanguageCode: "en-US",
              SubtitleFormats: "vtt",
              Destination: {
                Mode: "AWS/S3",
                BucketName: CONFIG.PORTER_TEST_BUCKET_NAME,
                ObjectKey: "test/transcribe-invalid-subtitle-format/transcript.json"
              }
            }
          ]
        }
      }

      job_test(job) do |output|
        _(output["JobResult"]["Job"]["Id"]).must_equal "porter-test-transcribe-invalid-subtitle-format"
        _(output["JobResult"]["State"]).must_equal "DONE"
        _(output["JobResult"]["TaskResults"]).must_equal []
        _(output["JobResult"]["FailedTasks"].length).must_equal 1
      end
    end
  end
end
