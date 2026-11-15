# frozen_string_literal: true

# Runs hls.rb end to end without an AWS account
#   ruby test/harness/run_local.rb <source> <outdir> [breaks]
# breaks is a comma list of seconds, or JSON for ranges: '[10.5,[14.7,16.2],20.383]'
require "json"
require_relative "task_runner"

source = ARGV[0] or abort "usage: run_local.rb <source> <outdir> [breaks]"
outdir = ARGV[1] or abort "usage: run_local.rb <source> <outdir> [breaks]"
raw_breaks = ARGV[2] || "10.5,14.717,20.383"
breaks = raw_breaks.start_with?("[") ? JSON.parse(raw_breaks) : raw_breaks.split(",").map(&:to_f)

abort "no such source: #{source}" unless File.file?(source)
FileUtils.mkdir_p(outdir)
outdir = File.expand_path(outdir)

puts JSON.dump({
  msg: "harness starting",
  source: File.expand_path(source),
  outdir: outdir,
  breaks: breaks
})

run = TaskRunner.run(
  source: source,
  task: {
    "Type" => "HLS",
    "Preset" => "Standard Podcast 2026 v1",
    "AdBreaks" => breaks
  },
  upload_to: outdir,
  capture: false
)

if run.failure
  warn JSON.dump({
    msg: "harness: task FAILED",
    error: run.failure[:error],
    cause: run.failure[:cause]
  })
  exit 1
end

abort "harness: task is not ok" unless run.ok?

result_path = File.join(outdir, "task-result.json")
File.write(result_path, JSON.pretty_generate(run.task_result) + "\n")

puts JSON.dump({
  msg: "harness done",
  objects: run.uploaded.length,
  result: result_path
})

run.uploaded.sort_by { |u| u[:key] }.each do |u|
  puts format("  %-22s %-40s %9d bytes", u[:key], u[:content_type], u[:bytes])
end
