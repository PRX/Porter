/* eslint-disable max-classes-per-file */
// Because the result of a Fargate task is not sufficient for sending a proper
// callback, this function takes the entire task input and builds a better
// result that gets passed to the callback task. The Fargate tasks should
// always write a JSON file with information about the execution to S3. If it
// includes an Error property, the FTP execution was unsuccessful, and this
// Lambda should throw an error, to proxy the failure up to the state machine.
// If the FTP operation was successful, there won't be an Error property, but
// could be other properties like Mode, etc. All such properties will be
// included in the task result.

const AWSXRay = require('aws-xray-sdk');

const AWS = AWSXRay.captureAWS(require('aws-sdk'));

const s3 = new AWS.S3({ apiVersion: '2006-03-01' });

class MissingFtpResultsError extends Error {
  constructor(...params) {
    super(...params);
    this.name = 'MissingFtpResultsError';
  }
}

class FtpOperationError extends Error {
  constructor(...params) {
    super(...params);
    this.name = 'FtpOperationError';
  }
}

exports.handler = async (event) => {
  console.log(JSON.stringify({ msg: 'State input', input: event }));

  const file = await s3
    .getObject({
      Bucket: process.env.ARTIFACT_BUCKET_NAME,
      Key: `${event.Execution.Id}/copy/ftp-result-${event.TaskIteratorIndex}.json`,
    })
    .promise();
  const ftpResult = JSON.parse(file.Body.toString());

  if (!ftpResult) {
    throw new MissingFtpResultsError('No Fargate results file found');
  } else if (ftpResult.Error) {
    // If the Fargate experienced an issue, reraise it here so it's visible
    // within the state machine
    // TODO Possible to throw the actual error class?
    throw new FtpOperationError(
      `${ftpResult.Error}: ${ftpResult.ErrorMessage}`,
    );
  } else {
    const now = new Date();

    const result = {
      Task: event.Task.Type,
      URL: event.Task.URL,
      ...ftpResult,
      Time: now.toISOString(),
      Timestamp: +now / 1000,
    };

    console.log(JSON.stringify({ msg: 'Result', result }));

    return result;
  }
};
