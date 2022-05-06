// const { Storage } = require('@google-cloud/storage');

module.exports = async function main(event) {
  // Copies a file in Google Cloud Storage to the S3 artifact bucket.
  // https://googleapis.dev/nodejs/storage/latest/index.html
  // https://googleapis.dev/nodejs/storage/latest/Bucket.html#getFiles
  // https://cloud.google.com/storage/docs/json_api/v1/objects/get
  // https://github.com/googleapis/nodejs-storage/blob/main/samples/downloadFile.js
  // const storage = new Storage({
  //   projectId: event.Job.Source.ProjectId,
  //   credentials: event.Job.Source.Credentials,
  // });
  console.log(event);
};
