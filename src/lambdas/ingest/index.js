// This function is invoked at the start of a state machine execution, and
// ingests the source file declared in the job to a short-term S3 bucket.
// Subsequent states in the step function access the file from that location.
// Source files can be ingested from either S3 or HTTP origins.
//
// The input for this state is the original job object that was sent as input
// to the state machine execution, eg:
// { "Job": { "Id": "xyz", "Source": { "URI": "s3://myBucket/myObject" }, … } }
//
// The input path for this Lambda function is explicitly defined parameters, eg
// { "Job": { "Source": { "URI": "s3://myBucket/myObject" } }, "Execution": { "Id": "x85a61ed-ff52-5291-debd-616797212639" } }
//
// The function returns an object like
// { "BucketName": "abc", "ObjectKey": "xyz" }
//
// The result path is $.Artifact, so the output of the state looks like
// { "Job": { … }, "Artifact": { "BucketName": "abc", "ObjectKey": "xyz" } }

const fromHttp = require('./source/http');
const fromDataUri = require('./source/data-uri');
const fromS3 = require('./source/aws-s3');
const fromGcpStorage = require('./source/gcp-storage');

class UnknownSourceModeError extends Error {
  constructor(...params) {
    super(...params);
    this.name = 'UnknownSourceModeError';
  }
}

/**
 *
 * @param {object} source
 * @returns
 */
function filenameFromSource(source) {
  if (source.Mode === 'HTTP') {
    const urlObj = new URL(source.URL);
    return (
      decodeURIComponent(urlObj.pathname.split('/').pop()) || urlObj.hostname
    );
  }

  if (source.Mode === 'AWS/S3') {
    return source.ObjectKey.split('/').pop();
  }

  if (source.Mode === 'GCP/Storage') {
    return source.ObjectName.split('/').pop();
  }

  return false;
}
exports.filenameFromSource = filenameFromSource;

exports.handler = async (event, context) => {
  console.log(JSON.stringify({ msg: 'State input', input: event }));

  const sourceFilename = filenameFromSource(event.Job.Source);

  const artifact = {
    BucketName: process.env.ARTIFACT_BUCKET_NAME,
    ObjectKey: `${event.Execution.Id}/${context.awsRequestId}/${sourceFilename}`,
  };

  switch (event.Job.Source.Mode) {
    case 'HTTP':
      await fromHttp(event, artifact, sourceFilename);
      break;
    case 'AWS/S3':
      await fromS3(event, artifact);
      break;
    case 'Data/URI':
      await fromDataUri(event, artifact);
      break;
    case 'GCP/Storage':
      await fromGcpStorage(event, artifact, sourceFilename);
      break;
    default:
      throw new UnknownSourceModeError('Unexpected source mode');
  }

  return artifact;
};
