# frozen_string_literal: true

require "test_helper"
require "json"

describe :porter do
  parallelize_me!

  describe :hls do
    it "returns execution output for an HLS task with ad breaks" do
      # The sample is a clip of Big Buck Bunny, (c) copyright 2008 Blender
      # Foundation / www.bigbuckbunny.org, used under CC BY 3.0.
      # See test/samples/README.md
      #
      # It is a 1080p source, which is where preset's ladder tops out at.
      #
      # The break times deliberately do not all land on whole frames;
      # tests when ActualTime differs from the request for two of the three breaks:
      #
      #   10.5    -> frame 315.000, already exact      ->  +0.000 ms
      #   14.717  -> frame 441.510, rounds UP to 442   -> +16.333 ms
      #   20.383  -> frame 611.490, rounds DOWN to 611 -> -16.333 ms
      job = {
        Job: {
          Id: "porter-test-hls",
          Source: {
            Mode: "HTTP",
            URL: "https://raw.githubusercontent.com/PRX/Porter/master/test/samples/big-buck-bunny-30s.mp4"
          },
          Tasks: [
            {
              Type: "HLS",
              Preset: "Standard Podcast 2026 v1",
              AdBreaks: [10.5, 14.717, 20.383],
              Destination: {
                Mode: "AWS/S3",
                BucketName: CONFIG.PORTER_TEST_BUCKET_NAME,
                ObjectKeyPrefix: "dev/sample/hls/"
              }
            }
          ]
        }
      }

      # A real multi-rendition encode, so this needs considerably longer than the
      # audio tasks: five renditions come out of one decode pass.
      job_test(job, 10) do |output|
        _(output["JobResult"]["Job"]["Id"]).must_equal "porter-test-hls"
        _(output["JobResult"]["State"]).must_equal "DONE"
        _(output["JobResult"]["FailedTasks"]).must_equal []
        _(output["JobResult"]["TaskResults"].length).must_equal 1

        result = output["JobResult"]["TaskResults"][0]

        breaks = result["AdBreaks"]

        # break requests comes back verbatim for matching/validating
        _(breaks.map { |b| b["RequestedTime"] }).must_equal [10.5, 14.717, 20.383]

        # boundaries to actually splice at, quantized to whole frames
        _(breaks.map { |b| b["ActualTime"] }).must_equal [10.5, 14.733333, 20.366667]

        # Half a frame at 30 fps is 16.67 ms, so no actual should exceed that
        breaks.each do |b|
          _((b["ActualTime"] - b["RequestedTime"]).abs).must_be :<=, 1.0 / 60 + 1e-9
        end

        # which actual segment in the m3u8 the break falls after, for splicing into the playlist
        _(breaks.map { |b| b["InsertAfterSegmentIndex"] }).must_equal [1, 2, 4]

        # Every label the preset publishes (i.e. POSSIBLE_LABELS)
        labels = result["Assets"]["Variants"].map { |v| v["PresetLabel"] }
        _(labels.sort).must_equal %w[AUDIO 480P 720P 1080P IFRAME].sort

        # Both masters, for now the compatibility is less used.
        _(result["Assets"]["MasterPlaylist"]["ObjectKey"]).must_match(/index\.m3u8\z/)
        _(result["Assets"]["CompatibilityMasterPlaylist"]["ObjectKey"])
          .must_match(/index-compat\.m3u8\z/)
      end
    end

    it "omits break metadata when no ad breaks are requested" do
      # AdBreaks is optional, so the plain-grid path has to keep working
      job = {
        Job: {
          Id: "porter-test-hls-no-breaks",
          Source: {
            Mode: "HTTP",
            URL: "https://raw.githubusercontent.com/PRX/Porter/master/test/samples/big-buck-bunny-30s.mp4"
          },
          Tasks: [
            {
              Type: "HLS",
              Preset: "Standard Podcast 2026 v1",
              Destination: {
                Mode: "AWS/S3",
                BucketName: CONFIG.PORTER_TEST_BUCKET_NAME,
                ObjectKeyPrefix: "dev/sample/hls-no-breaks/"
              }
            }
          ]
        }
      }

      job_test(job, 10) do |output|
        _(output["JobResult"]["State"]).must_equal "DONE"
        _(output["JobResult"]["FailedTasks"]).must_equal []

        result = output["JobResult"]["TaskResults"][0]
        _(result["AdBreaks"]).must_be_nil
        _(result["Assets"]["Variants"].map { |v| v["PresetLabel"] }).must_include "IFRAME"
      end
    end
  end
end
