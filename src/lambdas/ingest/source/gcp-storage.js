import { Storage } from '@google-cloud/storage';
import { tmpdir } from 'node:os';
import { join as pathJoin } from 'node:path';
import { createReadStream, unlinkSync } from 'node:fs';
import { S3Client } from '@aws-sdk/client-s3';
import { Upload } from '@aws-sdk/lib-storage';

const s3 = new S3Client({ apiVersion: '2006-03-01' });

export default async function main(event, artifact, sourceFilename) {
  // Copies a file in Google Cloud Storage to the S3 artifact bucket.
  // https://googleapis.dev/nodejs/storage/latest/index.html
  // https://googleapis.dev/nodejs/storage/latest/Bucket.html#getFiles
  // https://cloud.google.com/storage/docs/json_api/v1/objects/get
  // https://github.com/googleapis/nodejs-storage/blob/main/samples/downloadFile.js
  const storage = new Storage({
    projectId: event.Job.Source.ProjectId,
    credentials: event.Job.Source.ClientConfiguration,
  });

  const localFilePath = pathJoin(tmpdir(), sourceFilename);

  // Downloads the file from GCP
  await storage
    .bucket(event.Job.Source.BucketName)
    .file(event.Job.Source.ObjectName)
    .download({
      destination: localFilePath,
    });

  // Upload the artifact to S3
  await new Upload({
    client: s3,
    params: {
      Bucket: artifact.BucketName,
      Key: artifact.ObjectKey,
      Body: createReadStream(localFilePath),
    },
  }).done();

  unlinkSync(localFilePath);
}
