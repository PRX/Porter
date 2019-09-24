const AWSXRay = require('aws-xray-sdk');

const AWS = AWSXRay.captureAWS(require('aws-sdk'));

const stepfunctions = new AWS.StepFunctions({ apiVersion: '2016-11-23' });

exports.handler = async (event) => {
  await stepfunctions.startExecution({
    stateMachineArn: process.env.STATE_MACHINE_ARN,
    input: event.Records[0].Sns.Message
  }).promise();
};
