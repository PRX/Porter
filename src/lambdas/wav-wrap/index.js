import { createHash } from 'node:crypto';
import { S3Client, GetObjectCommand } from '@aws-sdk/client-s3';
import { STSClient, AssumeRoleCommand } from '@aws-sdk/client-sts';
import { Upload } from '@aws-sdk/lib-storage';
import wavefile from 'prx-wavefile';

function camelize(str) {
  return str
    .replace(/(?:^\w|[A-Z]|\b\w)/g, (word, index) =>
      index === 0 ? word.toLowerCase() : word.toUpperCase(),
    )
    .replace(/\s+/g, '');
}

/**
 *
 * @param {STSClient} sts
 * @param {*} event
 * @param {Uint8Array} uploadBuffer
 */
async function s3Upload(sts, event, uploadBuffer) {
  const role = await sts.send(
    new AssumeRoleCommand({
      RoleArn: process.env.S3_DESTINATION_WRITER_ROLE,
      RoleSessionName: 'porter_wavwrapper_task',
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
    Body: uploadBuffer,
    Metadata: {},
  };

  // When the optional `ContentType` property is set to `REPLACE`, if a MIME is
  // included with the artifact, that should be used as the new audio file's
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

export const handler = async (event) => {
  console.log(JSON.stringify({ msg: 'State input', input: event }));

  const s3 = new S3Client({
    apiVersion: '2006-03-01',
    followRegionRedirects: true,
  });
  const sts = new STSClient({ apiVersion: '2011-06-15' });

  // Fetch the source file artifact from S3 into memory
  const s3Object = await s3.send(
    new GetObjectCommand({
      Bucket: event.Artifact.BucketName,
      Key: event.Artifact.ObjectKey,
    }),
  );
  const mpegData = await s3Object.Body.transformToByteArray();

  // create the wav object
  const wav = new wavefile.WaveFile();

  // only if the task explicitly turns off pad byte
  if (event.Task.NoPadByte === true) {
    wav.padBytes = false;
  }

  if (mpegData instanceof Uint8Array || Buffer.isBuffer(mpegData)) {
    wav.fromMpeg(mpegData);
  } else {
    throw new Error(
      'No suitable mpeg buffer found to set up WaveFileCreator object',
    );
  }

  // If there are chunks passed in, iterate through each
  const resultChunks = [];
  event.Task.Chunks.forEach((taskChunk) => {
    // Set data if this is a chunk supported by wavefile
    const chunkId = taskChunk.ChunkId;
    if (Object.prototype.hasOwnProperty.call(wav, chunkId)) {
      Object.keys(taskChunk).forEach((taskKey) => {
        const wavKey = camelize(taskKey);
        if (
          !['chunkSize'].includes(wavKey) &&
          Object.prototype.hasOwnProperty.call(wav[chunkId], wavKey)
        ) {
          wav[chunkId][wavKey] = taskChunk[taskKey];
        }
      });
      resultChunks.push(wav[chunkId]);
    }
  });

  console.log(
    JSON.stringify({
      msg: 'Wavefile chunks set',
      chunks: resultChunks,
    }),
  );

  // save to s3 destination
  if (event.Task.Destination.Mode === 'AWS/S3') {
    await s3Upload(sts, event, Buffer.from(wav.toBuffer()));
  }

  const now = new Date();

  return {
    Task: 'WavWrap',
    Mode: event.Task.Destination.Mode,
    BucketName: event.Task.Destination.BucketName,
    ObjectKey: event.Task.Destination.ObjectKey,
    Time: now.toISOString(),
    Timestamp: +now / 1000,
    WavefileChunks: resultChunks,
  };
};
