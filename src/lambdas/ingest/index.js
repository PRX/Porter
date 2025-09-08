// This function is invoked at the start of a state machine execution, and
// ingests the source file declared in the job to a short-term S3 bucket.
// Subsequent states in the step function access the file from that location.
// Source files can be ingested from either S3 or HTTP origins.
//
// The input for this state is the original job object that was sent as input
// to the state machine execution, eg:
// { "Job": { "Id": "xyz", "Source": { "URI": "s3://myBucket/myObject" }, … } }
//
// The input path for this Lambda function is explicitly defined parameters, eg
// { "Job": { "Source": { "URI": "s3://myBucket/myObject" } }, "Execution": { "Id": "x85a61ed-ff52-5291-debd-616797212639" } }
//
// The function returns an object like
// { "BucketName": "abc", "ObjectKey": "xyz" }
//
// The result path is $.Artifact, so the output of the state looks like
// { "Job": { … }, "Artifact": { "BucketName": "abc", "ObjectKey": "xyz" } }
// eslint-disable-next-line import/no-extraneous-dependencies
import { HeadObjectCommand, S3Client } from "@aws-sdk/client-s3";
import fromS3 from "./source/aws-s3.js";
import fromDataUri from "./source/data-uri.js";
import fromGcpStorage from "./source/gcp-storage.js";
import fromHttp from "./source/http.js";

const s3 = new S3Client({
  apiVersion: "2006-03-01",
  followRegionRedirects: true,
});

class UnknownSourceModeError extends Error {
  constructor(...params) {
    super(...params);
    this.name = "UnknownSourceModeError";
  }
}

/**
 *
 * @param {object} source
 * @returns
 */
export function filenameFromSource(source) {
  if (source.Mode === "HTTP") {
    const urlObj = new URL(source.URL);
    return (
      decodeURIComponent(urlObj.pathname.split("/").pop()) || urlObj.hostname
    );
  }

  if (source.Mode === "AWS/S3") {
    return source.ObjectKey.split("/").pop();
  }

  if (source.Mode === "GCP/Storage") {
    return source.ObjectName.split("/").pop();
  }

  return false;
}

export const handler = async (event, context) => {
  console.log(JSON.stringify({ msg: "State input", input: event }));

  const sourceFilename = filenameFromSource(event.Job.Source);

  const artifact = {
    BucketName: process.env.ARTIFACT_BUCKET_NAME,
    ObjectKey: `${event.Execution.Id}/${context.awsRequestId}/${sourceFilename}`,
  };

  switch (event.Job.Source.Mode) {
    case "HTTP":
      await fromHttp(event, artifact);
      break;
    case "AWS/S3":
      await fromS3(event, artifact);
      break;
    case "Data/URI":
      await fromDataUri(event, artifact);
      break;
    case "GCP/Storage":
      await fromGcpStorage(event, artifact);
      break;
    default:
      throw new UnknownSourceModeError("Unexpected source mode");
  }

  // Add the file size of the actual object that was written to S3 to the
  // artifact output
  const head = await s3.send(
    new HeadObjectCommand({
      Bucket: artifact.BucketName,
      Key: artifact.ObjectKey,
    }),
  );
  artifact.ContentLength = head.ContentLength;

  return artifact;
};
