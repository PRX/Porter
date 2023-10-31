import { CloudWatch, PutMetricDataCommand } from '@aws-sdk/client-cloudwatch';

const cloudwatch = new CloudWatch({ region: process.env.AWS_REGION });

export default async function send(event) {
  // This is to avoid sending metrics during the test suite
  if (event.StateMachine) {
    await cloudwatch.send(
      new PutMetricDataCommand({
        Namespace: 'PRX/Porter',
        MetricData: [
          {
            MetricName: 'JobsStarted',
            Dimensions: [
              {
                Name: 'StateMachineArn',
                Value: event.StateMachine.Id,
              },
            ],
            Value: 1,
            Unit: 'Count',
          },
          {
            MetricName: 'TasksRequested',
            Dimensions: [
              {
                Name: 'StateMachineArn',
                Value: event.StateMachine.Id,
              },
            ],
            Value: event.Input.Job.Tasks.length,
            Unit: 'Count',
          },
        ],
      }),
    );
  }
}
