// This function relays messages from an SNS topic to a Step Function state
// machine. It passes the SNS message directly to the state machine as
// the execution input.

const { SFNClient, StartExecutionCommand } = require('@aws-sdk/client-sfn');

const sfnClient = new SFNClient({});

exports.handler = async (event) => {
  console.log(
    JSON.stringify({
      msg: 'Starting execution',
      job: event.Records[0].Sns.Message,
    }),
  );

  await sfnClient.send(
    new StartExecutionCommand({
      stateMachineArn: process.env.STATE_MACHINE_ARN,
      input: event.Records[0].Sns.Message,
    }),
  );
};
