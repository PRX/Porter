const sharp = require('sharp');

const { S3Client, GetObjectCommand } = require('@aws-sdk/client-s3');
const { STSClient, AssumeRoleCommand } = require('@aws-sdk/client-sts');
const { Upload } = require('@aws-sdk/lib-storage');

const s3Client = new S3Client({});
const stsClient = new STSClient({});

/** @typedef {import('stream')} Readable */
/**
 * @param {*} s3ObjectBody
 * @return {s3ObjectBody is Readable}
 */
function bodyIsReadable(s3ObjectBody) {
  if (Object.prototype.hasOwnProperty.call(s3ObjectBody, 'pipe')) {
    return true;
  }

  return false;
}

function sharpTransformer(event) {
  let transform = sharp();

  if (Object.prototype.hasOwnProperty.call(event.Task, 'Resize')) {
    transform = transform.resize({
      width: event.Task.Resize.Width,
      height: event.Task.Resize.Height,
      position: event.Task.Resize.Position || 'centre',
      fit: event.Task.Resize.Fit || 'cover',
    });
  }

  if (Object.prototype.hasOwnProperty.call(event.Task, 'Format')) {
    transform = transform.toFormat(event.Task.Format);
  }

  if (
    Object.prototype.hasOwnProperty.call(event.Task, 'Metadata') &&
    event.Task.Metadata === 'PRESERVE'
  ) {
    transform = transform.withMetadata();
  }

  return transform;
}

async function s3Upload(event, readableStream) {
  const role = await stsClient.send(
    new AssumeRoleCommand({
      RoleArn: process.env.S3_DESTINATION_WRITER_ROLE,
      RoleSessionName: 'porter_image_task',
    }),
  );

  const destWriterS3Client = new S3Client({
    credentials: {
      accessKeyId: role.Credentials.AccessKeyId,
      secretAccessKey: role.Credentials.SecretAccessKey,
      sessionToken: role.Credentials.SessionToken,
    },
  });

  const params = {
    Bucket: event.Task.Destination.BucketName,
    Key: event.Task.Destination.ObjectKey,
    Body: readableStream,
  };

  // When the optional `ContentType` property is set to `REPLACE`, if a MIME is
  // included with the artifact, that should be used as the new images's
  // content type
  if (
    Object.prototype.hasOwnProperty.call(
      event.Task.Destination,
      'ContentType',
    ) &&
    event.Task.Destination.ContentType === 'REPLACE' &&
    Object.prototype.hasOwnProperty.call(event.Artifact, 'Descriptor') &&
    Object.prototype.hasOwnProperty.call(event.Artifact.Descriptor, 'MIME')
  ) {
    params.ContentType = event.Artifact.Descriptor.MIME;
  }

  // Assign all members of Parameters to params. Remove the properties required
  // for the Copy operation, so there is no collision
  if (
    Object.prototype.hasOwnProperty.call(event.Task.Destination, 'Parameters')
  ) {
    delete event.Task.Destination.Parameters.Bucket;
    delete event.Task.Destination.Parameters.Key;
    delete event.Task.Destination.Parameters.Body;

    Object.assign(params, event.Task.Destination.Parameters);
  }

  // Upload the resulting file to the destination in S3
  const uploadStart = process.hrtime();

  const upload = new Upload({
    client: destWriterS3Client,
    params,
  });
  await upload.done();

  const uploadEnd = process.hrtime(uploadStart);
  console.log(
    JSON.stringify({
      msg: 'Finished S3 upload',
      duration: `${uploadEnd[0]} s ${uploadEnd[1] / 1000000} ms`,
    }),
  );
}

exports.handler = async (event) => {
  console.log(JSON.stringify({ msg: 'State input', input: event }));

  // Fetch the source file artifact from S3
  console.log(
    JSON.stringify({
      msg: 'Fetching artifact from S3',
      s3: `${event.Artifact.BucketName}/${event.Artifact.ObjectKey}`,
    }),
  );

  const artifactObject = await s3Client.send(
    new GetObjectCommand({
      Bucket: event.Artifact.BucketName,
      Key: event.Artifact.ObjectKey,
    }),
  );

  // Pipe the file data to sharp
  let transformed;
  if (bodyIsReadable(artifactObject.Body)) {
    transformed = artifactObject.Body.pipe(sharpTransformer());
  } else {
    throw new Error('Unexpected S3 object Body type');
  }

  const now = new Date();
  const result = {
    Task: 'Image',
    Time: now.toISOString(),
    Timestamp: +now / 1000,
  };

  if (event.Task.Destination.Mode === 'AWS/S3') {
    await s3Upload(event, transformed);

    Object.assign(result, {
      BucketName: event.Task.Destination.BucketName,
      ObjectKey: event.Task.Destination.ObjectKey,
    });
  }

  return result;
};
