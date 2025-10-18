import { createReadStream } from "node:fs";
import { GetObjectCommand, S3Client } from "@aws-sdk/client-s3";
import { sdkStreamMixin } from "@smithy/util-stream";
import { mockClient } from "aws-sdk-client-mock";
import { handler } from "../../../src/lambdas/inspect/index.js";
import "aws-sdk-client-mock-jest";

const s3Mock = mockClient(S3Client);

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
        MatchTags: "AIS_AD_BREAK_",
      },
    },
    {
      awsRequestId: "test-request-id",
    },
  );
  expect(result.Task).toEqual("Inspect");
  expect(result.Inspection.Audio.Tags).toEqual({
    comment: "AIS_AD_BREAK_1=2000,0;",
  });
}, 20000);
