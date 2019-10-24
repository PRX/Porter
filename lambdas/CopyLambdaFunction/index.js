const AWSXRay = require('aws-xray-sdk');

const AWS = AWSXRay.captureAWS(require('aws-sdk'));

const s3 = new AWS.S3({ apiVersion: '2006-03-01' });

// https://docs.aws.amazon.com/AWSJavaScriptSDK/latest/AWS/S3.html#copyObject-property
// https://docs.aws.amazon.com/AmazonS3/latest/API/RESTObjectCOPY.html
// CopySource expects: "/sourcebucket/path/to/object.extension"
async function awsS3copyObject(event) {
  console.log(JSON.stringify({
    msg: 'S3 Copy',
    source: `${event.Artifact.BucketName}/${event.Artifact.ObjectKey}`,
    destination: `${event.Task.BucketName}/${event.Task.ObjectKey}`
  }));

  const params = {
    CopySource: `/${event.Artifact.BucketName}/${event.Artifact.ObjectKey}`,
    Bucket: event.Task.BucketName,
    Key: event.Task.ObjectKey
  };


  // When the optional `ContentType` property is set to `REPLACE`, if a MIME is
  // included with the artifact, that should be used as the copy's content type
  if (event.Task.hasOwnProperty('ContentType')
      && event.Task.ContentType === 'REPLACE'
      && event.Artifact.hasOwnProperty('Descriptor')
      && event.Artifact.Descriptor.hasOwnProperty('MIME')) {
    params.MetadataDirective = 'REPLACE';
    params.ContentType = event.Artifact.Descriptor.MIME;
  }

  // Assign all members of Parameters to params. Remove the properties required
  // for the Copy operation, so there is no collision
  if (event.Task.hasOwnProperty('Parameters')) {
    delete event.Task.Parameters.CopySource;
    delete event.Task.Parameters.Bucket;
    delete event.Task.Parameters.Key;

    Object.assign(params, event.Task.Parameters);
  }

  const _start = process.hrtime();
  await s3.copyObject(params).promise();
  const _end = process.hrtime(_start);

  console.log(JSON.stringify({
    msg: 'Finished S3 Copy',
    duration: `${_end[0]} s ${_end[1] / 1000000} ms`,
  }));
}

exports.handler = async (event) => {
  console.log(JSON.stringify({ msg: 'State input', input: event }));

  if (event.Task.Mode === 'AWS/S3') {
    // TODO Detect if the source file is > 5 GB and do a multipart upload to
    // create the copy
    await awsS3copyObject(event);
  } else {
    throw new Error('Unexpected copy mode');
  }

  const now = new Date;

  return {
    Task: 'Copy',
    Mode: event.Task.Mode,
    BucketName: event.Task.BucketName,
    ObjectKey: event.Task.ObjectKey,
    Time: now.toISOString(),
    Timestamp: (now / 1000)
  };
};
