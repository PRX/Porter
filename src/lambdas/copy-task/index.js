const toAwsS3 = require('./destination/aws-s3');
const toGcpStorage = require('./destination/gcp-storage');

class UnknownCopyTaskModeError extends Error {
  constructor(...params) {
    super(...params);
    this.name = 'UnknownCopyTaskModeError';
  }
}

exports.handler = async (event, context) => {
  console.log(JSON.stringify({ msg: 'State input', input: event }));

  switch (event.Task.Mode) {
    case 'AWS/S3':
      await toAwsS3(event, context);
      break;
    case 'GCP/Storage':
      await toGcpStorage(event);
      break;
    default:
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
