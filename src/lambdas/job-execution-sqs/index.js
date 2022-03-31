// This function relays messages from an SQS queue to a Step Function state
// machine. It passes the SNS message directly to the state machine as
// the execution input.

const AWS = require('aws-sdk');

const stepfunctions = new AWS.StepFunctions({ apiVersion: '2016-11-23' });

exports.handler = async (event) => {
  console.log(
    JSON.stringify({
      msg: 'Starting execution',
      job: event.Records[0].body,
    }),
  );

  await stepfunctions
    .startExecution({
      stateMachineArn: process.env.STATE_MACHINE_ARN,
      input: event.Records[0].body,
    })
    .promise();
};
