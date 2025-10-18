import { writeFile } from "node:fs/promises";
import { tmpdir } from "node:os";
import { join as pathJoin } from "node:path";
import { GetObjectCommand, S3Client } from "@aws-sdk/client-s3";
import { AssumeRoleCommand, STSClient } from "@aws-sdk/client-sts";
import { Upload } from "@aws-sdk/lib-storage";

/**
 * @typedef {object} LambdaEvent
 * @property {DestinationTask} Task
 */

/**
 * @typedef {object} DestinationTask
 * @property {AwsS3Destination|GCPStorageDestination} Destination
 */

/**
 * @typedef {object} AwsS3Destination
 * @property {"AWS/S3"} Mode
 * @property {string} BucketName
 * @property {string} ObjectKey
 * @property {"REPLACE"} [ContentType]
 * @property {PutObjectRequest} [Parameters]
 */

/**
 * @typedef {object} GCPStorageDestination
 * @property {"GCP/Storage"} Mode
 */

const s3 = new S3Client({
  apiVersion: "2006-03-01",
  followRegionRedirects: true,
});
const sts = new STSClient({ apiVersion: "2011-06-15" });

export class UnknownDestinationModeError extends Error {
  constructor(...params) {
    super(...params);
    this.name = "UnknownDestinationModeError";
  }
}

/** Fetches the job's source file artifact from S3 and writes it to the Lambda
 * environment's local temp storage.
 * @returns {Promise<string>} Path to the file that was written
 */
export async function writeArtifact(event, context) {
  const ext = event.Artifact.Descriptor.Extension;
  const tmpFilePath = pathJoin(tmpdir(), `${context.awsRequestId}.${ext}`);

  const { Body } = await s3.send(
    new GetObjectCommand({
      Bucket: event.Artifact.BucketName,
      Key: event.Artifact.ObjectKey,
    }),
  );

  // @ts-expect-error
  await writeFile(tmpFilePath, Body);

  return tmpFilePath;
}

/**
 * @param {LambdaEvent} event
 * @param {StreamingBlobPayloadInputTypes} body
 */
async function sendToAwsS3(event, body) {
  // Assume the static S3 Destination Writer role
  const role = await sts.send(
    new AssumeRoleCommand({
      RoleArn: process.env.S3_DESTINATION_WRITER_ROLE,
      RoleSessionName: "porter_task_destination",
    }),
  );

  // Create an S3 Client using the S3 Destination Writer role
  const s3writer = new S3Client({
    apiVersion: "2006-03-01",
    credentials: {
      accessKeyId: role.Credentials.AccessKeyId,
      secretAccessKey: role.Credentials.SecretAccessKey,
      sessionToken: role.Credentials.SessionToken,
    },
    followRegionRedirects: true,
  });

  const params = {
    Bucket: event.Task.Destination.BucketName,
    Key: event.Task.Destination.ObjectKey,
    Body: body,
  };

  // When the optional `ContentType` property is set to `REPLACE`, if a MIME is
  // included with the artifact, that should be used as the new images's
  // content type
  if (
    Object.hasOwn(event.Task.Destination, "ContentType") &&
    event.Task.Destination.ContentType === "REPLACE" &&
    Object.hasOwn(event.Artifact, "Descriptor") &&
    Object.hasOwn(event.Artifact.Descriptor, "MIME")
  ) {
    params.ContentType = event.Artifact.Descriptor.MIME;
  }

  // Assign all members of Parameters to params. Remove the properties required
  // for the Copy operation, so there is no collision
  if (Object.hasOwn(event.Task.Destination, "Parameters")) {
    delete event.Task.Destination.Parameters.Bucket;
    delete event.Task.Destination.Parameters.Key;
    delete event.Task.Destination.Parameters.Body;

    Object.assign(params, event.Task.Destination.Parameters);
  }

  // Upload the data to the destination in S3
  const upload = new Upload({ client: s3writer, params });
  await upload.done();
}

/**
 *
 * @param {LambdaEvent} event
 */
async function sendToGCPStorage(event) {
  return event;
}

/**
 * Utility function to send task result data to various destinations. The data
 * is expected to be
 * @param {LambdaEvent} event
 * @param {StreamingBlobPayloadInputTypes} body
 */
export async function sendToDestination(event, body) {
  if (event.Task.Destination.Mode === "AWS/S3") {
    await sendToAwsS3(event, body);
  } else if (event.Task.Destination.Mode === "GCP/Storage") {
    await sendToGCPStorage(event);
  } else {
    throw new UnknownDestinationModeError(
      `Unexpected destination mode: ${event.Task.Destination.Mode}`,
    );
  }
}

// set the binary directory path based on the environment
export function binDir(bin) {
  const path = process.env.BIN_DIR || "/opt/bin";
  return pathJoin(path, bin);
}
