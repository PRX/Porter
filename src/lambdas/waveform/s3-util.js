import { createWriteStream, createReadStream } from 'node:fs';
import { S3Client, GetObjectCommand } from '@aws-sdk/client-s3';
import { STSClient, AssumeRoleCommand } from '@aws-sdk/client-sts';
import { Upload } from '@aws-sdk/lib-storage';

const s3 = new S3Client({
  apiVersion: '2006-03-01',
  followRegionRedirects: true,
});
const sts = new STSClient({ apiVersion: '2011-06-15' });

/**
 * Downloads the given S3 object to a local file path
 * @param {string} bucketName
 * @param {string} objectKey
 * @param {string} filePath
 */
export function s3GetObject(bucketName, objectKey, filePath) {
  // eslint-disable-next-line no-async-promise-executor
  return new Promise(async (resolve, reject) => {
    const file = createWriteStream(filePath);

    const resp = await s3.send(
      new GetObjectCommand({
        Bucket: bucketName,
        Key: objectKey,
      }),
    );

    const stream = resp.Body;

    // @ts-ignore
    stream.pipe(file);

    // @ts-ignore
    stream.on('error', reject);
    file.on('error', reject);

    file.on('finish', () => {
      resolve(filePath);
    });
  });
}

/**
 * Downloads the artifact from the Lambda input to a local file path
 * @param {object} event
 * @param {string} filePath
 */
export async function fetchArtifact(event, filePath) {
  console.log(
    JSON.stringify({
      msg: 'Fetching artifact from S3',
      s3: `${event.Artifact.BucketName}/${event.Artifact.ObjectKey}`,
      fs: filePath,
    }),
  );

  const s3start = process.hrtime();
  await s3GetObject(
    event.Artifact.BucketName,
    event.Artifact.ObjectKey,
    filePath,
  );

  const s3end = process.hrtime(s3start);
  console.log(
    JSON.stringify({
      msg: 'Fetched artifact from S3',
      duration: `${s3end[0]} s ${s3end[1] / 1000000} ms`,
    }),
  );
}

export async function s3Upload(event, waveformFileTmpPath) {
  const role = await sts.send(
    new AssumeRoleCommand({
      RoleArn: process.env.S3_DESTINATION_WRITER_ROLE,
      RoleSessionName: 'porter_waveform_task',
    }),
  );

  const s3writer = new S3Client({
    apiVersion: '2006-03-01',
    credentials: {
      accessKeyId: role.Credentials.AccessKeyId,
      secretAccessKey: role.Credentials.SecretAccessKey,
      sessionToken: role.Credentials.SessionToken,
    },
    followRegionRedirects: true,
  });

  const params = {
    Bucket: event.Task.Destination.BucketName,
    Key: event.Task.Destination.ObjectKey,
    Body: createReadStream(waveformFileTmpPath),
  };

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
  const upload = new Upload({ client: s3writer, params });
  await upload.done();
  const uploadEnd = process.hrtime(uploadStart);
  console.log(
    JSON.stringify({
      msg: 'Finished S3 upload',
      duration: `${uploadEnd[0]} s ${uploadEnd[1] / 1000000} ms`,
    }),
  );
}
