const path = require('path');
const os = require('os');
const fs = require('fs');
// eslint-disable-next-line import/no-extraneous-dependencies
const AWS = require('aws-sdk');
// eslint-disable-next-line import/no-extraneous-dependencies
const { Storage } = require('@google-cloud/storage');

const s3 = new AWS.S3({ apiVersion: '2006-03-01' });

module.exports = async function main(event, artifact, sourceFilename) {
  // Copies a file in Google Cloud Storage to the S3 artifact bucket.
  // https://googleapis.dev/nodejs/storage/latest/index.html
  // https://googleapis.dev/nodejs/storage/latest/Bucket.html#getFiles
  // https://cloud.google.com/storage/docs/json_api/v1/objects/get
  // https://github.com/googleapis/nodejs-storage/blob/main/samples/downloadFile.js
  const storage = new Storage({
    projectId: event.Job.Source.ProjectId,
    credentials: event.Job.Source.ClientConfiguration,
  });

  const localFilePath = path.join(os.tmpdir(), sourceFilename);

  // Downloads the file from GCP
  await storage
    .bucket(event.Job.Source.BucketName)
    .file(event.Job.Source.ObjectName)
    .download({
      destination: localFilePath,
    });

  // Upload the artifact to S3
  await s3
    .upload({
      Bucket: artifact.BucketName,
      Key: artifact.ObjectKey,
      Body: fs.createReadStream(localFilePath),
    })
    .promise();
};
