// This function relays messages from an SNS topic to a Step Function state
// machine. It passes the SNS message directly to the state machine as
// the execution input.

import { SFN, StartExecutionCommand } from '@aws-sdk/client-sfn';

const sfn = new SFN();

export const handler = async (event) => {
  console.log(
    JSON.stringify({
      msg: 'Starting execution',
      job: event.Records[0].Sns.Message,
    }),
  );

  await sfn.send(
    new StartExecutionCommand({
      stateMachineArn: process.env.STATE_MACHINE_ARN,
      input: event.Records[0].Sns.Message,
    }),
  );
};
