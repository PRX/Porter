# frozen_string_literal: true

require "test_helper"
require "json"

describe :porter do
  parallelize_me!

  describe :image do
    it "returns execution output for an image task" do
      job = {
        Job: {
          Id: "porter-test-image-resize",
          Source: {
            Mode: "Data/URI",
            URI: "data:image/gif;base64,R0lGODlhAQABAIAAAAAAAP///yH5BAEAAAAALAAAAAABAAEAAAIBRAA7"
          },
          Tasks: [
            {
              Type: "Image",
              Resize: {
                Height: 50,
                Width: 50
              },
              Destination: {
                Mode: "AWS/S3",
                BucketName: CONFIG.PORTER_TEST_BUCKET_NAME,
                ObjectKey: "dev/sample/image/image.jpg"
              }
            }
          ]
        }
      }

      job_test(job) do |output|
        _(output["JobResult"]["Job"]["Id"]).must_equal "porter-test-image-resize"
        _(output["JobResult"]["State"]).must_equal "DONE"
        _(output["JobResult"]["FailedTasks"]).must_equal []
        _(output["JobResult"]["TaskResults"].length).must_equal 1
      end
    end
  end
end
