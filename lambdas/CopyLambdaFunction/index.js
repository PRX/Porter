const AWSXRay = require('aws-xray-sdk');

const AWS = AWSXRay.captureAWS(require('aws-sdk'));

const s3 = new AWS.S3({ apiVersion: '2006-03-01' });

// Ex. input:  { "Artifact": { "BucketName": "SourceBucket", "ObjectKey": "Abc.wav" }, "Copy": { "Mode": "AWS/S3", "BucketName": "DestinationBucket", "ObjectKey": "AbcCopy.wav" } }
// Ex. output: { "Task": "Copy", "BucketName": "ResultBucket", "ObjectKey": "AbcCopy.wav", "Time": "2012-12-21T12:34:56Z", "Timestamp": 12345678 }
exports.handler = async (event) => {
  if (event.Copy.Mode === 'AWS/S3') {
    // https://docs.aws.amazon.com/AWSJavaScriptSDK/latest/AWS/S3.html#copyObject-property
    // https://docs.aws.amazon.com/AmazonS3/latest/API/RESTObjectCOPY.html
    // CopySource expects: "/sourcebucket/path/to/object.extension"
    await s3.copyObject({
      CopySource: `/${event.Artifact.BucketName}/${event.Artifact.ObjectKey}`,
      Bucket: event.Copy.BucketName,
      Key: event.Copy.ObjectKey
    }).promise();

    console.log(`Copied /${event.Artifact.BucketName}/${event.Artifact.ObjectKey} to /${event.Copy.BucketName}/${event.Copy.ObjectKey}`);
  } else {
    throw new Error('Unexpected copy mode');
  }

  const now = new Date;

  return {
    Task: 'Copy',
    BucketName: event.Copy.BucketName,
    ObjectKey: event.Copy.ObjectKey,
    Time: now.toISOString(),
    Timestamp: (now / 1000)
  };
};
