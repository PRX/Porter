import { Storage } from "@google-cloud/storage";
import { S3Client } from "@aws-sdk/client-s3";
import { Upload } from "@aws-sdk/lib-storage";

const s3 = new S3Client({
  apiVersion: "2006-03-01",
  followRegionRedirects: true,
});

export default async function main(event, artifact) {
  // Copies a file in Google Cloud Storage to the S3 artifact bucket.
  // https://googleapis.dev/nodejs/storage/latest/index.html
  // https://googleapis.dev/nodejs/storage/latest/Bucket.html#getFiles
  // https://cloud.google.com/storage/docs/json_api/v1/objects/get
  // https://github.com/googleapis/nodejs-storage/blob/main/samples/downloadFile.js
  const storage = new Storage({
    projectId: event.Job.Source.ProjectId,
    credentials: event.Job.Source.ClientConfiguration,
  });

  // Create a readable stream from the GCP object
  const readable = await storage
    .bucket(event.Job.Source.BucketName)
    .file(event.Job.Source.ObjectName)
    .createReadStream();

  // Stream the object data to S3
  const upload = new Upload({
    client: s3,
    params: {
      Bucket: artifact.BucketName,
      Key: artifact.ObjectKey,
      Body: readable,
    },
  });
  await upload.done();
}
