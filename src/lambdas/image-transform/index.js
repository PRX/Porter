import { S3Client, GetObjectCommand } from '@aws-sdk/client-s3';
import { STSClient, AssumeRoleCommand } from '@aws-sdk/client-sts';
import { Upload } from '@aws-sdk/lib-storage';
import { tmpdir } from 'node:os';
import {
  createReadStream,
  createWriteStream,
  mkdirSync,
  unlinkSync,
} from 'node:fs';
import { join as pathJoin } from 'node:path';
import sharp from 'sharp';

const s3 = new S3Client({ apiVersion: '2006-03-01' });
const sts = new STSClient({ apiVersion: '2011-06-15' });

function transform(inputFile, outputFile, event) {
  return new Promise((resolve, reject) => {
    try {
      let process;

      process = sharp(inputFile);

      if (Object.hasOwn(event.Task, 'Resize')) {
        process = process.resize({
          width: event.Task.Resize.Width,
          height: event.Task.Resize.Height,
          position: event.Task.Resize.Position || 'centre',
          fit: event.Task.Resize.Fit || 'cover',
        });
      }

      if (Object.hasOwn(event.Task, 'Format')) {
        process = process.toFormat(event.Task.Format);
      }

      if (
        Object.hasOwn(event.Task, 'Metadata') &&
        event.Task.Metadata === 'PRESERVE'
      ) {
        process = process.withMetadata();
      }

      process.toFile(outputFile, (error, info) => {
        if (error) {
          reject(error);
        } else {
          resolve(info);
        }
      });
    } catch (error) {
      reject(error);
    }
  });
}

/**
 * Downloads the given S3 object to a local file path
 * @param {string} bucketName
 * @param {string} objectKey
 * @param {string} filePath
 */
function s3GetObject(bucketName, objectKey, filePath) {
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

async function s3Upload(event, imageFileTmpPath) {
  const role = await sts.send(
    new AssumeRoleCommand({
      RoleArn: process.env.S3_DESTINATION_WRITER_ROLE,
      RoleSessionName: 'porter_image_task',
    }),
  );

  const s3writer = new S3Client({
    apiVersion: '2006-03-01',
    credentials: {
      accessKeyId: role.Credentials.AccessKeyId,
      secretAccessKey: role.Credentials.SecretAccessKey,
      sessionToken: role.Credentials.SessionToken,
    },
  });

  const params = {
    Bucket: event.Task.Destination.BucketName,
    Key: event.Task.Destination.ObjectKey,
    Body: createReadStream(imageFileTmpPath),
  };

  // When the optional `ContentType` property is set to `REPLACE`, if a MIME is
  // included with the artifact, that should be used as the new images's
  // content type
  if (
    Object.hasOwn(event.Task.Destination, 'ContentType') &&
    event.Task.Destination.ContentType === 'REPLACE' &&
    Object.hasOwn(event.Artifact, 'Descriptor') &&
    Object.hasOwn(event.Artifact.Descriptor, 'MIME')
  ) {
    params.ContentType = event.Artifact.Descriptor.MIME;
  }

  // Assign all members of Parameters to params. Remove the properties required
  // for the Copy operation, so there is no collision
  if (Object.hasOwn(event.Task.Destination, 'Parameters')) {
    delete event.Task.Destination.Parameters.Bucket;
    delete event.Task.Destination.Parameters.Key;
    delete event.Task.Destination.Parameters.Body;

    Object.assign(params, event.Task.Destination.Parameters);
  }

  // Upload the resulting file to the destination in S3
  const uploadStart = process.hrtime();
  await new Upload({ client: s3writer, params });
  const uploadEnd = process.hrtime(uploadStart);
  console.log(
    JSON.stringify({
      msg: 'Finished S3 upload',
      duration: `${uploadEnd[0]} s ${uploadEnd[1] / 1000000} ms`,
    }),
  );
}

export const handler = async (event, context) => {
  console.log(JSON.stringify({ msg: 'State input', input: event }));

  mkdirSync(pathJoin(tmpdir(), context.awsRequestId));

  const artifactFileTmpPath = pathJoin(
    tmpdir(),
    context.awsRequestId,
    'artifact',
  );

  // Fetch the source file artifact from S3
  console.log(
    JSON.stringify({
      msg: 'Fetching artifact from S3',
      s3: `${event.Artifact.BucketName}/${event.Artifact.ObjectKey}`,
      fs: artifactFileTmpPath,
    }),
  );

  const s3start = process.hrtime();
  await s3GetObject(
    event.Artifact.BucketName,
    event.Artifact.ObjectKey,
    artifactFileTmpPath,
  );

  const s3end = process.hrtime(s3start);
  console.log(
    JSON.stringify({
      msg: 'Fetched artifact from S3',
      duration: `${s3end[0]} s ${s3end[1] / 1000000} ms`,
    }),
  );

  // Run the file through sharp
  const sharpStart = process.hrtime();

  const imageFileTmpPath = pathJoin(tmpdir(), context.awsRequestId, 'output');

  await transform(artifactFileTmpPath, imageFileTmpPath, event);

  const sharpEnd = process.hrtime(sharpStart);
  console.log(
    JSON.stringify({
      msg: 'Finished image processing',
      duration: `${sharpEnd[0]} s ${sharpEnd[1] / 1000000} ms`,
    }),
  );

  if (event.Task.Destination.Mode === 'AWS/S3') {
    await s3Upload(event, imageFileTmpPath);
  }

  unlinkSync(artifactFileTmpPath);
  unlinkSync(imageFileTmpPath);

  const now = new Date();

  return {
    Task: 'Image',
    Mode: event.Task.Destination.Mode,
    BucketName: event.Task.Destination.BucketName,
    ObjectKey: event.Task.Destination.ObjectKey,
    Time: now.toISOString(),
    Timestamp: +now / 1000,
  };
};
