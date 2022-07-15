const AWS = require('aws-sdk');
const md5 = require('md5');
const path = require('path');
const os = require('os');
const fs = require('fs');

const sts = new AWS.STS({ apiVersion: '2011-06-15' });
const s3reader = new AWS.S3({ apiVersion: '2006-03-01' });

class AwsS3MultipartCopyError extends Error {
  constructor(...params) {
    super(...params);
    this.name = 'AwsS3MultipartCopyError';
  }
}

function buildParams(event, sourceFileMd5) {
  // CopySource expects: "/sourcebucket/path/to/object.extension"
  // CopySource expects "/sourcebucket/path/to/object.extension" to be URI-encoded
  const copySource = encodeURI(
    `/${event.Artifact.BucketName}/${event.Artifact.ObjectKey}`,
  ).replace(/\+/g, '%2B');

  // These will be the params passed to copyObject and createMultipartUpload
  // The Porter job artifact is the source, the Bucket and Object defined on
  // the copy task are the destination
  const params = {
    CopySource: copySource, // Source bucket and key
    Bucket: event.Task.BucketName, // Destination bucket
    Key: event.Task.ObjectKey, // Destination object key
    // eslint-disable-next-line no-buffer-constructor
    ContentMD5: new Buffer(sourceFileMd5, 'hex').toString('base64'),
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

  return params;
}

// https://aws.amazon.com/blogs/storage/copying-objects-greater-than-5-gb-with-amazon-s3-batch-operations/
// Look for max_concurrency for some info on performance tuning
async function multipartCopy(params, sourceObjectSize, s3Client) {
  // Initialize the multipart upload
  const multipartUpload = await s3Client
    .createMultipartUpload(params)
    .promise();

  const uploadId = multipartUpload.UploadId;

  // All parts except the last part will be this size. The last part will be
  // whatever is left over, and always less than or equal to this.
  const MiB = 2 ** 20; // 2^20 bytes = 1 MiB
  const targetPartSizeInBytes = 16 * MiB; // min 5 MiB, max 5 GiB

  // There's a maximum of 10,000 parts per multi-part upload. Calculate the
  // size of each part if the source object were split into the maximum number
  // of parts. Parts are always a whole number of bytes, so round this value
  // up to the nearest byte, to always stay below 10,000 after dividing (i.e.,
  // err on the side of fewer parts).
  const maxPartCount = 10000; // Limit set by S3
  const minPartSizeInBytes = Math.ceil(sourceObjectSize / maxPartCount);

  // If the target part size is smaller than the minimum, it would result in
  // more than 10,000 parts. Use the minimum instead to have larger parts and
  // stay below the limit.
  const partSizeInBytes = Math.max(targetPartSizeInBytes, minPartSizeInBytes);

  // Calculate the byte ranges for each part of the source file that we're
  // going to upload, based on the target part size
  const partCount = Math.ceil(sourceObjectSize / partSizeInBytes);
  const partRanges = new Array(partCount).fill(0).map((r, idx) => {
    // For part size of 10, these would be: 0, 10, 20, etc
    const start = idx * partSizeInBytes;
    // For part size of 10 these would be: 9, 19, 29, etc
    // This can never be outside the range of the source file's size, and the
    // copy range is zero-based, so it maxes out at 1 less than the size of the
    // source file
    const end = Math.min(sourceObjectSize - 1, (idx + 1) * partSizeInBytes - 1);
    // E.g., with a part size of 10, and a file size of 26:
    // [0, 9], [10, 19], [20, 25]
    return [start, end];
  });

  try {
    // Copy all parts in parallel
    const uploads = await Promise.all(
      partRanges.map((range, idx) =>
        s3Client
          .uploadPartCopy({
            Bucket: params.Bucket, // Destination bucket
            Key: params.Key, // Destination object key
            PartNumber: idx + 1, // Positive integer between 1 and 10,000
            UploadId: uploadId,
            // CopySource expects: "/sourcebucket/path/to/object.extension"
            // CopySource expects "/sourcebucket/path/to/object.extension" to be URI-encoded
            CopySource: params.CopySource,
            CopySourceRange: `bytes=${range.join('-')}`,
          })
          .promise(),
      ),
    );

    // Finalize the upload after all parts have been successfully copied
    await s3Client
      .completeMultipartUpload({
        Bucket: params.Bucket, // Destination bucket
        Key: params.Key, // Destination object key
        UploadId: uploadId,
        MultipartUpload: {
          Parts: uploads.map((u, idx) => ({
            ETag: u.CopyPartResult.ETag,
            PartNumber: idx + 1,
          })),
        },
      })
      .promise();
  } catch (error) {
    // Clean up the incomplete upload if it fails
    await s3Client
      .abortMultipartUpload({
        Bucket: params.Bucket, // Destination bucket
        Key: params.Key, // Destination object key
        UploadId: uploadId,
      })
      .promise();

    throw new AwsS3MultipartCopyError('Multipart copy was aborted');
  }
}

module.exports = async function main(event, context) {
  console.log(
    JSON.stringify({
      msg: 'S3 Copy',
      source: `${event.Artifact.BucketName}/${event.Artifact.ObjectKey}`,
      destination: `${event.Task.BucketName}/${event.Task.ObjectKey}`,
    }),
  );

  // ///////////////////////////////////////////////////////////////////////////
  // TODO Temporary
  fs.mkdirSync(path.join(os.tmpdir(), context.awsRequestId));

  function s3GetObject(bucketName, objectKey, filePath) {
    return new Promise((resolve, reject) => {
      const file = fs.createWriteStream(filePath);
      const stream = s3reader
        .getObject({
          Bucket: bucketName,
          Key: objectKey,
        })
        .createReadStream();

      stream.on('error', reject);
      file.on('error', reject);

      file.on('finish', () => {
        resolve(filePath);
      });

      stream.pipe(file);
    });
  }

  const sourceFileTmpPath = path.join(
    os.tmpdir(),
    context.awsRequestId,
    'sourceFile',
  );

  await s3GetObject(
    event.Artifact.BucketName,
    event.Artifact.ObjectKey,
    sourceFileTmpPath,
  );

  const data = fs.readFileSync(sourceFileTmpPath);
  const sourceFileMd5 = md5(data);
  fs.unlinkSync(sourceFileTmpPath);
  // ///////////////////////////////////////////////////////////////////////////

  const head = await s3reader
    .headObject({
      Bucket: event.Artifact.BucketName,
      Key: event.Artifact.ObjectKey,
    })
    .promise();

  const writerRole = await sts
    .assumeRole({
      RoleArn: process.env.S3_DESTINATION_WRITER_ROLE,
      RoleSessionName: 'porter_copy_task',
    })
    .promise();

  const s3writer = new AWS.S3({
    apiVersion: '2006-03-01',
    accessKeyId: writerRole.Credentials.AccessKeyId,
    secretAccessKey: writerRole.Credentials.SecretAccessKey,
    sessionToken: writerRole.Credentials.SessionToken,
  });

  const params = buildParams(event, sourceFileMd5);

  // S3 can perform a native copy of objects up to 5 GB using the CopyObject
  // API. For objects larger than 5 GB, a multi-part upload must be used.
  if (head.ContentLength < 5000000000) {
    // Copies an existing S3 object to the S3 artifact bucket.
    // https://docs.aws.amazon.com/AWSJavaScriptSDK/latest/AWS/S3.html#copyObject-property
    // https://docs.aws.amazon.com/AmazonS3/latest/API/RESTObjectCOPY.html
    await s3writer.copyObject(params).promise();
  } else {
    // Copies and object using parallelized copy operations for byte range
    // parts of the source object
    await multipartCopy(params, head.ContentLength, s3writer);
  }
};
