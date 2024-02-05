// This function relays messages from an SQS queue to a Step Function state
// machine. It passes the SNS message directly to the state machine as
// the execution input.

import { SFNClient, StartExecutionCommand } from "@aws-sdk/client-sfn";

const sfn = new SFNClient({ apiVersion: "2016-11-23" });

export const handler = async (event) => {
  console.log(
    JSON.stringify({
      msg: "Starting execution",
      job: event.Records[0].body,
    }),
  );

  await sfn.send(
    new StartExecutionCommand({
      stateMachineArn: process.env.STATE_MACHINE_ARN,
      input: event.Records[0].Sns.Message,
    }),
  );
};
