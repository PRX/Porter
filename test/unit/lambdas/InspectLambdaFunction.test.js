import { createReadStream } from "node:fs";
import { GetObjectCommand, S3Client } from "@aws-sdk/client-s3";
import { sdkStreamMixin } from "@smithy/util-stream";
import { mockClient } from "aws-sdk-client-mock";
import { handler } from "../../../src/lambdas/inspect/index.js";
import "aws-sdk-client-mock-jest";

const s3Mock = mockClient(S3Client);

test("Inspect a png image file for comments", async () => {
  const stream = createReadStream("./test/samples/testJoinChannel.png");
  process.env.S3_DESTINATION_WRITER_ROLE = "arn:thisisafake";
  const sdkStream = sdkStreamMixin(stream);
  s3Mock.on(GetObjectCommand).resolves({ Body: sdkStream });

  const result = await handler(
    {
      Artifact: {
        BucketName: "myStackName-artifactbucket-1hnyu12xzvbel",
        ObjectKey: "test000/c6cd0af8/test.png",
        Descriptor: {
          Extension: "png",
          MIME: "image/png",
        },
      },
      Job: {
        Id: "asdfghjkl1234567890",
      },
      Task: {
        Type: "Inspect",
        IncludeMetadata: {
          Keys: {
            StringMatches: "Comment",
          },
        },
      },
    },
    {
      awsRequestId: "test-request-id",
    },
  );

  expect(result.Task).toEqual("Inspect");
  expect(result.Inspection.Image.Tags).toEqual([
    { key: "Comment", value: "Created with GIMP" },
  ]);
});

test("Inspect an audio file for EBUR128 loudness", async () => {
  const stream = createReadStream("./test/samples/two-tone.mp3");
  process.env.S3_DESTINATION_WRITER_ROLE = "arn:thisisafake";
  const sdkStream = sdkStreamMixin(stream);
  s3Mock.on(GetObjectCommand).resolves({ Body: sdkStream });

  const result = await handler(
    {
      Artifact: {
        BucketName: "myStackName-artifactbucket-1hnyu12xzvbel",
        ObjectKey: "test000/c6cd0af8/test.mp3",
        Descriptor: {
          Extension: "mp3",
          MIME: "audio/mpeg",
        },
      },
      Job: {
        Id: "asdfghjkl1234567890",
      },
      Task: {
        Type: "Inspect",
        EBUR128: true,
      },
    },
    {
      awsRequestId: "test-request-id",
    },
  );

  expect(result.Task).toEqual("Inspect");
  expect(result.Inspection.Audio.LoudnessIntegrated).toEqual(-10.3);
  expect(result.Inspection.Audio.LoudnessTruePeak).toEqual(-8.32);
  expect(result.Inspection.Audio.LoudnessRange).toEqual(14.6);
});

test("Inspect an audio file for tags", async () => {
  const stream = createReadStream("./test/samples/two-tone.mp3");
  process.env.S3_DESTINATION_WRITER_ROLE = "arn:thisisafake";
  const sdkStream = sdkStreamMixin(stream);
  s3Mock.on(GetObjectCommand).resolves({ Body: sdkStream });

  const result = await handler(
    {
      Artifact: {
        BucketName: "myStackName-artifactbucket-1hnyu12xzvbel",
        ObjectKey: "test000/c6cd0af8/test.mp3",
        Descriptor: {
          Extension: "mp3",
          MIME: "audio/mpeg",
        },
      },
      Job: {
        Id: "asdfghjkl1234567890",
      },
      Task: {
        Type: "Inspect",
        IncludeMetadata: {
          Values: {
            StringMatches: "AIS_AD_BREAK_",
          },
        },
      },
    },
    {
      awsRequestId: "test-request-id",
    },
  );
  expect(result.Task).toEqual("Inspect");
  expect(result.Inspection.Audio.Tags).toEqual([
    { key: "comment", value: "AIS_AD_BREAK_1=2000,0;" },
  ]);
}, 20000);

test("Inspect a video file for tags", async () => {
  const stream = createReadStream("./test/samples/trax.mp4");
  process.env.S3_DESTINATION_WRITER_ROLE = "arn:thisisafake";
  const sdkStream = sdkStreamMixin(stream);
  s3Mock.on(GetObjectCommand).resolves({ Body: sdkStream });

  const result = await handler(
    {
      Artifact: {
        BucketName: "myStackName-artifactbucket-1hnyu12xzvbel",
        ObjectKey: "test000/c6cd0af8/test.mp4",
        Descriptor: {
          Extension: "mp4",
          MIME: "video/mp4",
        },
      },
      Job: {
        Id: "asdfghjkl1234567890",
      },
      Task: {
        Type: "Inspect",
        IncludeMetadata: {
          Keys: {
            StringMatches: "encoder",
          },
        },
      },
    },
    {
      awsRequestId: "test-request-id",
    },
  );

  expect(result.Task).toEqual("Inspect");
  expect(result.Inspection.Video.Tags).toEqual([
    { key: "encoder", value: "Lavf58.45.100" },
  ]);
});

