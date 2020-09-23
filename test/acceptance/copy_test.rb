require 'test_helper'
require 'aws-sdk-states'
require 'json'

step_functions = Aws::States::Client.new(
  region: 'us-east-1'
)

describe :porter do
  describe :copy do
    describe :to_key_with_spaces do
      it 'handles HTTP source files with spaces' do
        req = step_functions.start_execution({
          state_machine_arn: CONFIG.PORTER_STATE_MACHINE_ARN,
          input: {
            Job: {
              Id: 'porter-test-copy-http-spaces-to-spaces',
              Source: {
                Mode: 'HTTP',
                URL: 'https://dovetail-cdn-staging.prxu.org/815/dAsUFiIz68rzpns5Cv7XM36Pt8bBzbu7gn3ui6Hg8-o/input file with spaces.mp3'
              },
              Tasks: [
                {
                  Type: "Copy",
                  Mode: "AWS/S3",
                  BucketName: CONFIG.PORTER_TEST_BUCKET_NAME,
                  ObjectKey: "copied file with spaces"
                }
              ]
            }
          }.to_json
        })

        max_retries = 60
        retries = 0

        begin
          desc = step_functions.describe_execution({
            execution_arn: req.execution_arn,
          })

          raise RuntimeError if desc.status == 'RUNNING'
        rescue RuntimeError => e
          if retries <= max_retries
            retries += 1
            sleep 2
            retry
          else
            raise "Timeout: #{e.message}"
          end
        end

        output = JSON.parse(desc.output)

        _(output['JobResult']['Job']['Id']).must_equal 'porter-test-copy-http-spaces-to-spaces'
        _(output['JobResult']['State']).must_equal 'DONE'
        _(output['JobResult']['FailedTasks']).must_equal []
        _(output['JobResult']['TaskResults'].length).must_equal 1
      end

      it 'handles HTTP source files with encoded spaces' do
        req = step_functions.start_execution({
          state_machine_arn: CONFIG.PORTER_STATE_MACHINE_ARN,
          input: {
            Job: {
              Id: 'porter-test-copy-http-encoded-spaces-to-spaces',
              Source: {
                Mode: 'HTTP',
                URL: 'https://dovetail-cdn-staging.prxu.org/815/dAsUFiIz68rzpns5Cv7XM36Pt8bBzbu7gn3ui6Hg8-o/input%20file%20with%20spaces.mp3'
              },
              Tasks: [
                {
                  Type: "Copy",
                  Mode: "AWS/S3",
                  BucketName: CONFIG.PORTER_TEST_BUCKET_NAME,
                  ObjectKey: "copied file with spaces"
                }
              ]
            }
          }.to_json
        })

        max_retries = 60
        retries = 0

        begin
          desc = step_functions.describe_execution({
            execution_arn: req.execution_arn,
          })

          raise RuntimeError if desc.status == 'RUNNING'
        rescue RuntimeError => e
          if retries <= max_retries
            retries += 1
            sleep 2
            retry
          else
            raise "Timeout: #{e.message}"
          end
        end

        output = JSON.parse(desc.output)

        _(output['JobResult']['Job']['Id']).must_equal 'porter-test-copy-http-encoded-spaces-to-spaces'
        _(output['JobResult']['State']).must_equal 'DONE'
        _(output['JobResult']['FailedTasks']).must_equal []
        _(output['JobResult']['TaskResults'].length).must_equal 1
      end

      it 'handles HTTP source files with plus' do
        req = step_functions.start_execution({
          state_machine_arn: CONFIG.PORTER_STATE_MACHINE_ARN,
          input: {
            Job: {
              Id: 'porter-test-copy-http-plus-to-spaces',
              Source: {
                Mode: 'HTTP',
                URL: 'https://dovetail-cdn-staging.prxu.org/815/dAsUFiIz68rzpns5Cv7XM36Pt8bBzbu7gn3ui6Hg8-o/input+file+with+spaces.mp3'
              },
              Tasks: [
                {
                  Type: "Copy",
                  Mode: "AWS/S3",
                  BucketName: CONFIG.PORTER_TEST_BUCKET_NAME,
                  ObjectKey: "copied file with spaces"
                }
              ]
            }
          }.to_json
        })

        max_retries = 60
        retries = 0

        begin
          desc = step_functions.describe_execution({
            execution_arn: req.execution_arn,
          })

          raise RuntimeError if desc.status == 'RUNNING'
        rescue RuntimeError => e
          if retries <= max_retries
            retries += 1
            sleep 2
            retry
          else
            raise "Timeout: #{e.message}"
          end
        end

        output = JSON.parse(desc.output)

        _(output['JobResult']['Job']['Id']).must_equal 'porter-test-copy-http-plus-to-spaces'
        _(output['JobResult']['State']).must_equal 'DONE'
        _(output['JobResult']['FailedTasks']).must_equal []
        _(output['JobResult']['TaskResults'].length).must_equal 1
      end

      it 'handles HTTP source files with encoded plus' do
        req = step_functions.start_execution({
          state_machine_arn: CONFIG.PORTER_STATE_MACHINE_ARN,
          input: {
            Job: {
              Id: 'porter-test-copy-http-encoded-plus-to-spaces',
              Source: {
                Mode: 'HTTP',
                URL: 'https://dovetail-cdn-staging.prxu.org/815/dAsUFiIz68rzpns5Cv7XM36Pt8bBzbu7gn3ui6Hg8-o/input%2Bfile%2Bwith%2Bspaces.mp3'
              },
              Tasks: [
                {
                  Type: "Copy",
                  Mode: "AWS/S3",
                  BucketName: CONFIG.PORTER_TEST_BUCKET_NAME,
                  ObjectKey: "copied file with spaces"
                }
              ]
            }
          }.to_json
        })

        max_retries = 60
        retries = 0

        begin
          desc = step_functions.describe_execution({
            execution_arn: req.execution_arn,
          })

          raise RuntimeError if desc.status == 'RUNNING'
        rescue RuntimeError => e
          if retries <= max_retries
            retries += 1
            sleep 2
            retry
          else
            raise "Timeout: #{e.message}"
          end
        end

        output = JSON.parse(desc.output)

        _(output['JobResult']['Job']['Id']).must_equal 'porter-test-copy-http-encoded-plus-to-spaces'
        _(output['JobResult']['State']).must_equal 'DONE'
        _(output['JobResult']['FailedTasks']).must_equal []
        _(output['JobResult']['TaskResults'].length).must_equal 1
      end

      it 'handles HTTP source files with encoded percent' do
        req = step_functions.start_execution({
          state_machine_arn: CONFIG.PORTER_STATE_MACHINE_ARN,
          input: {
            Job: {
              Id: 'porter-test-copy-http-encoded-percent-to-spaces',
              Source: {
                Mode: 'HTTP',
                URL: 'https://dovetail-cdn-staging.prxu.org/815/dAsUFiIz68rzpns5Cv7XM36Pt8bBzbu7gn3ui6Hg8-o/input%25file%25with%25spaces.mp3'
              },
              Tasks: [
                {
                  Type: "Copy",
                  Mode: "AWS/S3",
                  BucketName: CONFIG.PORTER_TEST_BUCKET_NAME,
                  ObjectKey: "copied file with spaces"
                }
              ]
            }
          }.to_json
        })

        max_retries = 60
        retries = 0

        begin
          desc = step_functions.describe_execution({
            execution_arn: req.execution_arn,
          })

          raise RuntimeError if desc.status == 'RUNNING'
        rescue RuntimeError => e
          if retries <= max_retries
            retries += 1
            sleep 2
            retry
          else
            raise "Timeout: #{e.message}"
          end
        end

        output = JSON.parse(desc.output)

        _(output['JobResult']['Job']['Id']).must_equal 'porter-test-copy-http-encoded-percent-to-spaces'
        _(output['JobResult']['State']).must_equal 'DONE'
        _(output['JobResult']['FailedTasks']).must_equal []
        _(output['JobResult']['TaskResults'].length).must_equal 1
      end
    end

    describe :to_key_with_plus do
      it 'handles HTTP source files with spaces' do
        req = step_functions.start_execution({
          state_machine_arn: CONFIG.PORTER_STATE_MACHINE_ARN,
          input: {
            Job: {
              Id: 'porter-test-copy-http-spaces-to-plus',
              Source: {
                Mode: 'HTTP',
                URL: 'https://dovetail-cdn-staging.prxu.org/815/dAsUFiIz68rzpns5Cv7XM36Pt8bBzbu7gn3ui6Hg8-o/input file with spaces.mp3'
              },
              Tasks: [
                {
                  Type: "Copy",
                  Mode: "AWS/S3",
                  BucketName: CONFIG.PORTER_TEST_BUCKET_NAME,
                  ObjectKey: "copied+file+with+spaces"
                }
              ]
            }
          }.to_json
        })

        max_retries = 60
        retries = 0

        begin
          desc = step_functions.describe_execution({
            execution_arn: req.execution_arn,
          })

          raise RuntimeError if desc.status == 'RUNNING'
        rescue RuntimeError => e
          if retries <= max_retries
            retries += 1
            sleep 2
            retry
          else
            raise "Timeout: #{e.message}"
          end
        end

        output = JSON.parse(desc.output)

        _(output['JobResult']['Job']['Id']).must_equal 'porter-test-copy-http-spaces-to-plus'
        _(output['JobResult']['State']).must_equal 'DONE'
        _(output['JobResult']['FailedTasks']).must_equal []
        _(output['JobResult']['TaskResults'].length).must_equal 1
      end

      it 'handles HTTP source files with encoded spaces' do
        req = step_functions.start_execution({
          state_machine_arn: CONFIG.PORTER_STATE_MACHINE_ARN,
          input: {
            Job: {
              Id: 'porter-test-copy-http-encoded-spaces-to-plus',
              Source: {
                Mode: 'HTTP',
                URL: 'https://dovetail-cdn-staging.prxu.org/815/dAsUFiIz68rzpns5Cv7XM36Pt8bBzbu7gn3ui6Hg8-o/input%20file%20with%20spaces.mp3'
              },
              Tasks: [
                {
                  Type: "Copy",
                  Mode: "AWS/S3",
                  BucketName: CONFIG.PORTER_TEST_BUCKET_NAME,
                  ObjectKey: "copied+file+with+spaces"
                }
              ]
            }
          }.to_json
        })

        max_retries = 60
        retries = 0

        begin
          desc = step_functions.describe_execution({
            execution_arn: req.execution_arn,
          })

          raise RuntimeError if desc.status == 'RUNNING'
        rescue RuntimeError => e
          if retries <= max_retries
            retries += 1
            sleep 2
            retry
          else
            raise "Timeout: #{e.message}"
          end
        end

        output = JSON.parse(desc.output)

        _(output['JobResult']['Job']['Id']).must_equal 'porter-test-copy-http-encoded-spaces-to-plus'
        _(output['JobResult']['State']).must_equal 'DONE'
        _(output['JobResult']['FailedTasks']).must_equal []
        _(output['JobResult']['TaskResults'].length).must_equal 1
      end

      it 'handles HTTP source files with plus' do
        req = step_functions.start_execution({
          state_machine_arn: CONFIG.PORTER_STATE_MACHINE_ARN,
          input: {
            Job: {
              Id: 'porter-test-copy-http-plus-to-plus',
              Source: {
                Mode: 'HTTP',
                URL: 'https://dovetail-cdn-staging.prxu.org/815/dAsUFiIz68rzpns5Cv7XM36Pt8bBzbu7gn3ui6Hg8-o/input+file+with+spaces.mp3'
              },
              Tasks: [
                {
                  Type: "Copy",
                  Mode: "AWS/S3",
                  BucketName: CONFIG.PORTER_TEST_BUCKET_NAME,
                  ObjectKey: "copied+file+with+spaces"
                }
              ]
            }
          }.to_json
        })

        max_retries = 60
        retries = 0

        begin
          desc = step_functions.describe_execution({
            execution_arn: req.execution_arn,
          })

          raise RuntimeError if desc.status == 'RUNNING'
        rescue RuntimeError => e
          if retries <= max_retries
            retries += 1
            sleep 2
            retry
          else
            raise "Timeout: #{e.message}"
          end
        end

        output = JSON.parse(desc.output)

        _(output['JobResult']['Job']['Id']).must_equal 'porter-test-copy-http-plus-to-plus'
        _(output['JobResult']['State']).must_equal 'DONE'
        _(output['JobResult']['FailedTasks']).must_equal []
        _(output['JobResult']['TaskResults'].length).must_equal 1
      end

      it 'handles HTTP source files with encoded plus' do
        req = step_functions.start_execution({
          state_machine_arn: CONFIG.PORTER_STATE_MACHINE_ARN,
          input: {
            Job: {
              Id: 'porter-test-copy-http-encoded-plus-to-plus',
              Source: {
                Mode: 'HTTP',
                URL: 'https://dovetail-cdn-staging.prxu.org/815/dAsUFiIz68rzpns5Cv7XM36Pt8bBzbu7gn3ui6Hg8-o/input%2Bfile%2Bwith%2Bspaces.mp3'
              },
              Tasks: [
                {
                  Type: "Copy",
                  Mode: "AWS/S3",
                  BucketName: CONFIG.PORTER_TEST_BUCKET_NAME,
                  ObjectKey: "copied+file+with+spaces"
                }
              ]
            }
          }.to_json
        })

        max_retries = 60
        retries = 0

        begin
          desc = step_functions.describe_execution({
            execution_arn: req.execution_arn,
          })

          raise RuntimeError if desc.status == 'RUNNING'
        rescue RuntimeError => e
          if retries <= max_retries
            retries += 1
            sleep 2
            retry
          else
            raise "Timeout: #{e.message}"
          end
        end

        output = JSON.parse(desc.output)

        _(output['JobResult']['Job']['Id']).must_equal 'porter-test-copy-http-encoded-plus-to-plus'
        _(output['JobResult']['State']).must_equal 'DONE'
        _(output['JobResult']['FailedTasks']).must_equal []
        _(output['JobResult']['TaskResults'].length).must_equal 1
      end

      it 'handles HTTP source files with encoded percent' do
        req = step_functions.start_execution({
          state_machine_arn: CONFIG.PORTER_STATE_MACHINE_ARN,
          input: {
            Job: {
              Id: 'porter-test-copy-http-encoded-percent-to-plus',
              Source: {
                Mode: 'HTTP',
                URL: 'https://dovetail-cdn-staging.prxu.org/815/dAsUFiIz68rzpns5Cv7XM36Pt8bBzbu7gn3ui6Hg8-o/input%25file%25with%25spaces.mp3'
              },
              Tasks: [
                {
                  Type: "Copy",
                  Mode: "AWS/S3",
                  BucketName: CONFIG.PORTER_TEST_BUCKET_NAME,
                  ObjectKey: "copied+file+with+spaces"
                }
              ]
            }
          }.to_json
        })

        max_retries = 60
        retries = 0

        begin
          desc = step_functions.describe_execution({
            execution_arn: req.execution_arn,
          })

          raise RuntimeError if desc.status == 'RUNNING'
        rescue RuntimeError => e
          if retries <= max_retries
            retries += 1
            sleep 2
            retry
          else
            raise "Timeout: #{e.message}"
          end
        end

        output = JSON.parse(desc.output)

        _(output['JobResult']['Job']['Id']).must_equal 'porter-test-copy-http-encoded-percent-to-plus'
        _(output['JobResult']['State']).must_equal 'DONE'
        _(output['JobResult']['FailedTasks']).must_equal []
        _(output['JobResult']['TaskResults'].length).must_equal 1
      end
    end
  end
end
