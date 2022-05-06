// eslint-disable-next-line import/no-extraneous-dependencies
const AWS = require('aws-sdk');

const s3 = new AWS.S3({ apiVersion: '2006-03-01' });

class AwsS3MultipartCopyError extends Error {
  constructor(...params) {
    super(...params);
    this.name = 'AwsS3MultipartCopyError';
  }
}

// https://aws.amazon.com/blogs/storage/copying-objects-greater-than-5-gb-with-amazon-s3-batch-operations/
// Look for max_concurrency for some info on performance tuning
async function multipartCopy(copySource, artifact, sourceObjectSize) {
  // Initialize the multipart upload
  const multipartUpload = await s3
    .createMultipartUpload({ Bucket: artifact.Bucket, Key: artifact.ObjectKey })
    .promise();

  const uploadId = multipartUpload.UploadId;

  // All parts except the last part will be this size. The last part will be
  // whatever is left over, and always less than or equal to this.
  const targetPartSize = 2 ** 20 * 16; // min 5 MiB, max 5 GiB

  // Calculate the byte ranges for each part of the source file that we're
  // going to upload, based on the target part size
  const partCount = Math.ceil(sourceObjectSize / targetPartSize);
  const partRanges = new Array(partCount).fill(0).map((r, idx) => {
    // For part size of 10, these would be: 0, 10, 20, etc
    const start = idx * targetPartSize;
    // For part size of 10 these would be: 9, 19, 29, etc
    // This can never be outside the range of the source file's size, and the
    // copy range is zero-based, so it maxes out at 1 less than the size of the
    // source file
    const end = Math.min(sourceObjectSize - 1, (idx + 1) * targetPartSize - 1);
    // E.g., with a part size of 10, and a file size of 26:
    // [0, 9], [10, 19], [20, 25]
    return [start, end];
  });

  try {
    // Copy all parts in parallel
    const uploads = await Promise.all(
      partRanges.map((range, idx) =>
        s3
          .uploadPartCopy({
            Bucket: artifact.Bucket, // Destination bucket
            Key: artifact.ObjectKey, // Destination object key
            PartNumber: idx + 1, // Positive integer between 1 and 10,000
            UploadId: uploadId,
            // CopySource expects: "/sourcebucket/path/to/object.extension"
            // CopySource expects "/sourcebucket/path/to/object.extension" to be URI-encoded
            CopySource: copySource,
            CopySourceRange: `bytes=${range.join('-')}`,
          })
          .promise(),
      ),
    );

    // Finalize the upload after all parts have been successfully copied
    await s3
      .completeMultipartUpload({
        Bucket: artifact.Bucket, // Destination bucket
        Key: artifact.ObjectKey, // Destination object key
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
    s3.abortMultipartUpload({
      Bucket: artifact.Bucket, // Destination bucket
      Key: artifact.ObjectKey, // Destination object key
      UploadId: uploadId,
    }).promise();

    throw new AwsS3MultipartCopyError('Multipart copy was aborted');
  }
}

module.exports = async function main(event, artifact) {
  // CopySource expects: "/sourcebucket/path/to/object.extension"
  // CopySource expects "/sourcebucket/path/to/object.extension" to be URI-encoded
  const copySource = encodeURI(
    `/${event.Job.Source.BucketName}/${event.Job.Source.ObjectKey}`,
  ).replace(/\+/g, '%2B');

  const head = await s3
    .headObject({
      Bucket: event.Job.Source.BucketName,
      Key: event.Job.Source.ObjectKey,
    })
    .promise();

  // S3 can perform a native copy of objects up to 5 GB using the CopyObject
  // API. For objects larger than 5 GB, a multi-part upload must be used.
  if (head.ContentLength < 5000000000) {
    // Copies an existing S3 object to the S3 artifact bucket.
    // https://docs.aws.amazon.com/AWSJavaScriptSDK/latest/AWS/S3.html#copyObject-property
    // https://docs.aws.amazon.com/AmazonS3/latest/API/RESTObjectCOPY.html
    await s3
      .copyObject({
        CopySource: copySource,
        Bucket: artifact.BucketName,
        Key: artifact.ObjectKey,
      })
      .promise();
  } else {
    // Copies and object using parallelized copy operations for byte range
    // parts of the source object
    await multipartCopy(copySource, artifact, head.ContentLength);
  }
};
