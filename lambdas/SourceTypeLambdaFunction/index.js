const fileType = require('file-type');
const AWSXRay = require('aws-xray-sdk');

const AWS = AWSXRay.captureAWS(require('aws-sdk'));

const s3 = new AWS.S3({ apiVersion: '2006-03-01' });

exports.handler = async (event) => {
  const s3stream = s3.getObject({
    Bucket: event.Artifact.BucketName,
    Key: event.Artifact.ObjectKey,
    Range: `bytes=0-${fileType.minimumBytes}`
  }).createReadStream();

  const ftStream = await fileType.stream(s3stream);

  // Eg. {ext: 'mov', mime: 'video/quicktime'}
  // Returns `undefined` when there is no match.
  const result = ftStream.fileType;

  if (!result) { return {}; }

  return {
    Extension: result.ext,
    MIME: result.mime
  }
}
