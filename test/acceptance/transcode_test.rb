# frozen_string_literal: true

require "test_helper"
require "json"

describe :porter do
  describe :transcode do
    it "returns execution output for a transcode task" do
      job = {
        Job: {
          Id: "porter-test-transcode",
          Source: {
            Mode: "HTTP",
            URL: "https://dovetail.prxu.org/152/245d0fe2-4171-4ebf-bea3-69deff3e9336/short.mp3"
          },
          Tasks: [
            {
              Type: "Transcode",
              Format: "flac",
              Destination: {
                Mode: "AWS/S3",
                BucketName: CONFIG.PORTER_TEST_BUCKET_NAME,
                ObjectKey: "test/transcode-options/transcode.flac",
                Parameters: {
                  CacheControl: "max-age=604800",
                  ContentDisposition: "attachment; filename='download.flac'",
                  ContentType: "audio/flac"
                }
              },
              FFmpeg: {
                InputFileOptions: "-t 1",
                OutputFileOptions: "-metadata title=some_title"
              }
            }
          ]
        }
      }

      job_test(job, 5) do |output|
        _(output["JobResult"]["Job"]["Id"]).must_equal "porter-test-transcode"
        _(output["JobResult"]["State"]).must_equal "DONE"
        _(output["JobResult"]["FailedTasks"]).must_equal []
        _(output["JobResult"]["TaskResults"].length).must_equal 1
        _(output["JobResult"]["TaskResults"][0]["Duration"]).must_equal 1000
      end
    end

    it "inherits artifact type for output" do
      job = {
        Job: {
          Id: "porter-test-transcode-inherit",
          Source: {
            Mode: "HTTP",
            URL: "https://dovetail.prxu.org/152/245d0fe2-4171-4ebf-bea3-69deff3e9336/short.mp3"
          },
          Tasks: [
            {
              Type: "Transcode",
              Format: "INHERIT",
              Destination: {
                Mode: "AWS/S3",
                BucketName: CONFIG.PORTER_TEST_BUCKET_NAME,
                ObjectKey: "test/transcode-options/transcode-inherit.mp3",
                Parameters: {
                  CacheControl: "max-age=604800",
                  ContentDisposition: "attachment; filename='download.mp3'",
                  ContentType: "audio/mp3"
                }
              },
              FFmpeg: {
                InputFileOptions: "-t 1",
                OutputFileOptions: "-metadata title=some_title"
              }
            }
          ]
        }
      }

      job_test(job, 5) do |output|
        _(output["JobResult"]["Job"]["Id"]).must_equal "porter-test-transcode-inherit"
        _(output["JobResult"]["State"]).must_equal "DONE"
        _(output["JobResult"]["FailedTasks"]).must_equal []
        _(output["JobResult"]["TaskResults"].length).must_equal 1
        _(output["JobResult"]["TaskResults"][0]["Duration"]).must_be_close_to 1000, 50
      end
    end
  end
end
