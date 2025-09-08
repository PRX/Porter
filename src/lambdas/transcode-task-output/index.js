// Because the result of a Fargate task is not sufficient for sending a proper
// callback, this function takes the entire task input and builds a better
// result that gets passed to the callback task.
import { GetObjectCommand, S3Client } from "@aws-sdk/client-s3";
import { NodeHttpHandler } from "@smithy/node-http-handler";
import { ConfiguredRetryStrategy } from "@smithy/util-retry";

const retryStrategy = new ConfiguredRetryStrategy(
  5, // Max attempts
  (attempt) => 100 + attempt * 500,
);

const requestHandler = new NodeHttpHandler({
  connectionTimeout: 800,
  requestTimeout: 2000,
  socketTimeout: 500,
});

const s3 = new S3Client({
  apiVersion: "2006-03-01",
  followRegionRedirects: true,
  retryStrategy,
  requestHandler,
});

export const handler = async (event) => {
  console.log(JSON.stringify({ msg: "State input", input: event }));

  // Get ffprobe results
  const file = await s3.send(
    new GetObjectCommand({
      Bucket: process.env.ARTIFACT_BUCKET_NAME,
      Key: `${event.Execution.Id}/transcode/ffprobe-${event.TaskIteratorIndex}.json`,
    }),
  );
  const json = await file.Body.transformToString();
  const ffprobe = JSON.parse(json);

  const now = new Date();

  const result = {
    Task: event.Task.Type,
    BucketName: event.Task.Destination.BucketName,
    ObjectKey: event.Task.Destination.ObjectKey,
    Duration: +ffprobe.format.duration * 1000,
    Size: +ffprobe.format.size,
    Time: now.toISOString(),
    Timestamp: +now / 1000,
  };

  console.log(JSON.stringify({ msg: "Result", result }));

  return result;
};
