const AWS = require('aws-sdk');

const s3 = new AWS.S3({ apiVersion: '2006-03-01' });

module.exports = async function main(event, artifact) {
  // Copies an existing S3 object to the S3 artifact bucket.
  // https://docs.aws.amazon.com/AWSJavaScriptSDK/latest/AWS/S3.html#copyObject-property
  // https://docs.aws.amazon.com/AmazonS3/latest/API/RESTObjectCOPY.html
  // CopySource expects: "/sourcebucket/path/to/object.extension"
  // CopySource expects "/sourcebucket/path/to/object.extension" to be URI-encoded
  await s3
    .copyObject({
      CopySource: encodeURI(
        `/${event.Job.Source.BucketName}/${event.Job.Source.ObjectKey}`,
      ).replace(/\+/g, '%2B'),
      Bucket: artifact.BucketName,
      Key: artifact.ObjectKey,
    })
    .promise();
};
