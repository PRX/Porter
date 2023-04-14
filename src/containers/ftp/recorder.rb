# frozen_string_literal: true

# Recorder is a helper class for making calls out to cloudwatch put_metric_data
class Recorder
  attr_reader :cloudwatch, :namespace, :dimensions

  def initialize(cloudwatch, namespace, dimensions)
    @cloudwatch = cloudwatch || Aws::CloudWatch::Client.new
    @namespace = namespace
    @dimensions = dimensions
  end

  def record(metric, unit, val)
    md = {metric_name: metric, dimensions: dimensions, value: val, unit: unit}
    cloudwatch.put_metric_data({namespace: namespace, metric_data: [md]})
  end
end
