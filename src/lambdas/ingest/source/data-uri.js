const AWS = require('aws-sdk');

const s3 = new AWS.S3({ apiVersion: '2006-03-01' });

class InvalidDataUriError extends Error {
  constructor(...params) {
    super(...params);
    this.name = 'InvalidDataUriError';
  }
}

module.exports = async function main(event, artifact) {
  // e.g., data:image/gif;base64,R0lGODlhAQABAIAAAAAAAP///yH5BAEAAAAALAAAAAABAAEAAAIBRAA7
  const uri = event.Job.Source.URI;

  if (!/^data:[\w/+-]+;base64,/.test(uri)) {
    throw new InvalidDataUriError('Invalid Data URI');
  }

  const base64Data = uri.split(';base64,')[1];

  await s3
    .upload({
      Bucket: artifact.BucketName,
      Key: artifact.ObjectKey,
      Body: Buffer.from(base64Data, 'base64'),
    })
    .promise();
};
