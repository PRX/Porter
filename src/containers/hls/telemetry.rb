require "aws-sdk-cloudwatch"

CLOUDWATCH = Aws::CloudWatch::Client.new

def send_start_metric
  # Count the tasks in CloudWatch Metrics
  puts JSON.dump({msg: "Sending telemetry, execution counter"})
  CLOUDWATCH.put_metric_data({
    namespace: "PRX/Porter",
    metric_data: [
      {
        metric_name: "HlsExecutions",
        dimensions: [
          {
            name: "StateMachineName",
            value: ENV["STATE_MACHINE_NAME"]
          }
        ],
        value: 1,
        unit: "Count"
      }
    ]
  })
end

def send_end_metric(duration)
  # Record HLS duration in CloudWatch Metrics
  puts JSON.dump({msg: "Sending telemetry, HLS duration", duration: "#{duration} seconds"})
  CLOUDWATCH.put_metric_data({
    namespace: "PRX/Porter",
    metric_data: [
      {
        metric_name: "HlsDuration",
        dimensions: [
          {
            name: "StateMachineName",
            value: ENV["STATE_MACHINE_NAME"]
          }
        ],
        value: duration,
        unit: "Seconds"
      }
    ]
  })
end
