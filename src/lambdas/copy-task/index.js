const AWS = require('aws-sdk');

const sts = new AWS.STS({ apiVersion: '2011-06-15' });

class UnknownCopyTaskModeError extends Error {
  constructor(...params) {
    super(...params);
    this.name = 'UnknownCopyTaskModeError';
  }
}

// https://docs.aws.amazon.com/AWSJavaScriptSDK/latest/AWS/S3.html#copyObject-property
// https://docs.aws.amazon.com/AmazonS3/latest/API/RESTObjectCOPY.html
// CopySource expects: "/sourcebucket/path/to/object.extension"
// CopySource expects "/sourcebucket/path/to/object.extension" to be URI-encoded
async function awsS3copyObject(event) {
  console.log(
    JSON.stringify({
      msg: 'S3 Copy',
      source: `${event.Artifact.BucketName}/${event.Artifact.ObjectKey}`,
      destination: `${event.Task.BucketName}/${event.Task.ObjectKey}`,
    }),
  );

  const role = await sts
    .assumeRole({
      RoleArn: process.env.S3_DESTINATION_WRITER_ROLE,
      RoleSessionName: 'porter_copy_task',
    })
    .promise();

  const s3 = new AWS.S3({
    apiVersion: '2006-03-01',
    accessKeyId: role.Credentials.AccessKeyId,
    secretAccessKey: role.Credentials.SecretAccessKey,
    sessionToken: role.Credentials.SessionToken,
  });

  const params = {
    CopySource: encodeURI(
      `/${event.Artifact.BucketName}/${event.Artifact.ObjectKey}`,
    ).replace(/\+/g, '%2B'),
    Bucket: event.Task.BucketName,
    Key: event.Task.ObjectKey,
  };

  // When the optional `ContentType` property is set to `REPLACE`, if a MIME is
  // included with the artifact, that should be used as the copy's content type
  if (
    Object.prototype.hasOwnProperty.call(event.Task, 'ContentType') &&
    event.Task.ContentType === 'REPLACE' &&
    Object.prototype.hasOwnProperty.call(event.Artifact, 'Descriptor') &&
    Object.prototype.hasOwnProperty.call(event.Artifact.Descriptor, 'MIME')
  ) {
    params.MetadataDirective = 'REPLACE';
    params.ContentType = event.Artifact.Descriptor.MIME;
  }

  // Assign all members of Parameters to params. Remove the properties required
  // for the Copy operation, so there is no collision
  if (Object.prototype.hasOwnProperty.call(event.Task, 'Parameters')) {
    delete event.Task.Parameters.CopySource;
    delete event.Task.Parameters.Bucket;
    delete event.Task.Parameters.Key;

    Object.assign(params, event.Task.Parameters);
  }

  const start = process.hrtime();
  await s3.copyObject(params).promise();
  const end = process.hrtime(start);

  console.log(
    JSON.stringify({
      msg: 'Finished S3 Copy',
      duration: `${end[0]} s ${end[1] / 1000000} ms`,
    }),
  );
}

exports.handler = async (event) => {
  console.log(JSON.stringify({ msg: 'State input', input: event }));

  if (event.Task.Mode === 'AWS/S3') {
    // TODO Detect if the source file is > 5 GB and do a multipart upload to
    // create the copy
    await awsS3copyObject(event);
  } else {
    throw new UnknownCopyTaskModeError('Unexpected copy mode');
  }

  const now = new Date();

  return {
    Task: 'Copy',
    Mode: event.Task.Mode,
    BucketName: event.Task.BucketName,
    ObjectKey: event.Task.ObjectKey,
    Time: now.toISOString(),
    Timestamp: +now / 1000,
  };
};
