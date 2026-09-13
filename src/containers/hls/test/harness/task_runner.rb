# frozen_string_literal: true

require "aws-sdk-s3"
require "aws-sdk-states"
require "fileutils"
require "json"
require "stringio"
require "tmpdir"

# Runs hls.rb with the AWS edges faked, so the entrypoint can be driven from a
# test or from the local harness.
#
# Shared by test/hls_test.rb and test/harness/run_local.rb.
module TaskRunner
  CONTAINER = File.expand_path("../..", __dir__)

  Run = Struct.new(:source, :upload_to, :result, :failure, :uploaded, :output) do
    def ok? = !result.nil?

    def task_result = result && JSON.parse(result)
  end

  class << self
    attr_accessor :current

    # source     -- local file standing in for the S3 artifact
    # task       -- the STATE_MACHINE_TASK_JSON payload
    # upload_to  -- directory to write "uploaded" objects into, or nil to only record them
    # capture    -- swallow hls.rb's stdout (tests) or let it through (harness)
    def run(source:, task:, upload_to: nil, capture: true)
      install_stubs
      run = Run.new(source: File.expand_path(source), upload_to: upload_to,
        uploaded: [], output: nil)
      self.current = run

      set_env(task)
      run.output = execute(capture)
      run
    ensure
      self.current = nil
    end

    private

    def execute(capture)
      return in_scratch { |dir| Dir.chdir(dir) { load File.join(dir, "hls.rb") } } && nil unless capture

      buffer = StringIO.new
      original = $stdout
      begin
        $stdout = buffer
        in_scratch { |dir| Dir.chdir(dir) { load File.join(dir, "hls.rb") } }
      ensure
        $stdout = original
      end
      buffer.string
    end

    # hls.rb loads from and writes to the cwd, so give each run its own tmp dir
    def in_scratch
      if in_container?
        yield CONTAINER
      else
        Dir.mktmpdir("hls-task") do |dir|
          %w[hls.rb telemetry.rb destinations presets lib].each do |entry|
            File.symlink(File.join(CONTAINER, entry), File.join(dir, entry))
          end
          yield dir
        end
      end
    end

    def in_container? = Dir.pwd == CONTAINER && ENV["APP_HOME"]

    def install_stubs
      return if @installed

      Aws.config.update(
        region: "us-east-1",
        credentials: Aws::Credentials.new("task-runner", "task-runner"),
        stub_responses: true
      )

      Aws::S3::TransferManager.class_eval do
        define_method(:download_file) do |dest, **_params|
          FileUtils.cp(TaskRunner.current.source, dest)
          true
        end

        define_method(:upload_file) do |path, **params|
          run = TaskRunner.current
          if run.upload_to
            dest = File.join(run.upload_to, params.fetch(:key))
            FileUtils.mkdir_p(File.dirname(dest))
            FileUtils.cp(path, dest)
          end
          run.uploaded << {
            key: params[:key],
            content_type: params[:content_type],
            bytes: File.size(path)
          }
          true
        end
      end

      # hls.rb rescues its own failures and falls off the end without exit, so
      # the only way to see a failed task is the callback it reports it through.
      Aws::States::Client.class_eval do
        define_method(:send_task_success) do |args|
          TaskRunner.current.result = args[:output]
          {}
        end

        define_method(:send_task_failure) do |args|
          TaskRunner.current.failure = args
          {}
        end
      end

      @installed = true
    end

    def set_env(task)
      ENV["STATE_MACHINE_TASK_TYPE"] = "HLS"
      ENV["STATE_MACHINE_TASK_TOKEN"] = "task-runner-token"
      ENV["STATE_MACHINE_NAME"] = "task-runner"
      ENV["STATE_MACHINE_AWS_REGION"] = "us-east-1"
      ENV["STATE_MACHINE_ARTIFACT_BUCKET_NAME"] = "artifacts"
      ENV["STATE_MACHINE_ARTIFACT_OBJECT_KEY"] = File.basename(current.source)
      ENV["STATE_MACHINE_DESTINATION_BUCKET_NAME"] = "destination"
      ENV["STATE_MACHINE_DESTINATION_OBJECT_KEY_PREFIX"] = ""
      ENV["STATE_MACHINE_S3_DESTINATION_WRITER_ROLE"] =
        "arn:aws:iam::123456789012:role/task-runner"
      ENV["STATE_MACHINE_DESTINATION_JSON"] = JSON.dump({
        "Mode" => "AWS/S3", "BucketName" => "destination", "ObjectKeyPrefix" => ""
      })
      ENV["STATE_MACHINE_TASK_JSON"] = JSON.dump(task)
    end
  end
end
