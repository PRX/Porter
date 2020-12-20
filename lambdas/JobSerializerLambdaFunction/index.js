// A job definition can include serialized jobs. These are additional,
// independent job definitions that will be started once the initial job has
// completed all its tasks, and sent its job result callbacks.
//
// The serialized jobs are sent to an SNS topic, and the actual Step Function
// execution initialization in handled elsewhere (by the
// JobExecutionSnsTopicLambdaFunction).
//
// An ExecutionTrace is appended to the serialized job definition, which
// represents the execution IDs of the jobs that serialized other jobs prior to
// this one.

const { SNSClient, PublishCommand } = require('@aws-sdk/client-sns');

const snsClient = new SNSClient({});

exports.handler = async (event) => {
  console.log(JSON.stringify({ msg: 'State input', input: event }));

  event.SerializedJob.ExecutionTrace = [
    ...event.ExecutionTrace,
    event.Execution.Id,
  ];

  console.log(
    JSON.stringify({ msg: 'Serialized Job', input: event.SerializedJob }),
  );

  await snsClient.send(
    new PublishCommand({
      TopicArn: process.env.JOB_EXECUTION_SNS_TOPIC_ARN,
      Message: JSON.stringify(event.SerializedJob),
    }),
  );
};
