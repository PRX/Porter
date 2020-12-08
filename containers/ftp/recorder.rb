class Recorder
  attr_reader :cloudwatch, :namespace, :dimensions

  def initialize(cloudwatch, namespace, dimensions)
    @cloudwatch = cloudwatch || Aws::CloudWatch::Client.new
    @namespace = namespace
    @dimensions = dimensions
  end

  def record(metric, unit, value)
    cloudwatch.put_metric_data(
      {
        namespace: namespace,
        metric_data: [
          {
            metric_name: metric,
            dimensions: dimensions,
            value: value,
            unit: unit
          }
        ]
      }
    )
  end
end
