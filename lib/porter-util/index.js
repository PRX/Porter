import { join as pathJoin } from 'node:path';
import { tmpdir } from 'node:os';
import { S3Client, GetObjectCommand } from '@aws-sdk/client-s3';
import { writeFile } from 'node:fs/promises';

const s3 = new S3Client({
  apiVersion: '2006-03-01',
  followRegionRedirects: true,
});

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

  // @ts-ignore
  await writeFile(tmpFilePath, Body);

  return tmpFilePath;
}
