# frozen_string_literal: true

require 'test_helper'
require 'aws-sdk-states'
require 'json'

step_functions = Aws::States::Client.new(
  region: CONFIG.PORTER_STATE_MACHINE_ARN.split(':')[3]
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
                                                    URL: 'https://dovetail.prxu.org/152/245d0fe2-4171-4ebf-bea3-69deff3e9336/input file with spaces.mp3'
                                                  },
                                                  Tasks: [
                                                    {
                                                      Type: 'Copy',
                                                      Mode: 'AWS/S3',
                                                      BucketName: CONFIG.PORTER_TEST_BUCKET_NAME,
                                                      ObjectKey: 'copied file with spaces'
                                                    }
                                                  ]
                                                }
                                              }.to_json
                                            })

        max_retries = 60
        retries = 0

        begin
          desc = step_functions.describe_execution({
                                                    execution_arn: req.execution_arn
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
                                                    URL: 'https://dovetail.prxu.org/152/245d0fe2-4171-4ebf-bea3-69deff3e9336/input%20file%20with%20spaces.mp3'
                                                  },
                                                  Tasks: [
                                                    {
                                                      Type: 'Copy',
                                                      Mode: 'AWS/S3',
                                                      BucketName: CONFIG.PORTER_TEST_BUCKET_NAME,
                                                      ObjectKey: 'copied file with spaces'
                                                    }
                                                  ]
                                                }
                                              }.to_json
                                            })

        max_retries = 60
        retries = 0

        begin
          desc = step_functions.describe_execution({
                                                    execution_arn: req.execution_arn
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
                                                    URL: 'https://dovetail.prxu.org/152/245d0fe2-4171-4ebf-bea3-69deff3e9336/input+file+with+spaces.mp3'
                                                  },
                                                  Tasks: [
                                                    {
                                                      Type: 'Copy',
                                                      Mode: 'AWS/S3',
                                                      BucketName: CONFIG.PORTER_TEST_BUCKET_NAME,
                                                      ObjectKey: 'copied file with spaces'
                                                    }
                                                  ]
                                                }
                                              }.to_json
                                            })

        max_retries = 60
        retries = 0

        begin
          desc = step_functions.describe_execution({
                                                    execution_arn: req.execution_arn
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
                                                    URL: 'https://dovetail.prxu.org/152/245d0fe2-4171-4ebf-bea3-69deff3e9336/input%2Bfile%2Bwith%2Bspaces.mp3'
                                                  },
                                                  Tasks: [
                                                    {
                                                      Type: 'Copy',
                                                      Mode: 'AWS/S3',
                                                      BucketName: CONFIG.PORTER_TEST_BUCKET_NAME,
                                                      ObjectKey: 'copied file with spaces'
                                                    }
                                                  ]
                                                }
                                              }.to_json
                                            })

        max_retries = 60
        retries = 0

        begin
          desc = step_functions.describe_execution({
                                                    execution_arn: req.execution_arn
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
                                                    URL: 'https://placeimg.com/5/5/input%25file%25with%25spaces'
                                                  },
                                                  Tasks: [
                                                    {
                                                      Type: 'Copy',
                                                      Mode: 'AWS/S3',
                                                      BucketName: CONFIG.PORTER_TEST_BUCKET_NAME,
                                                      ObjectKey: 'copied file with spaces'
                                                    }
                                                  ]
                                                }
                                              }.to_json
                                            })

        max_retries = 60
        retries = 0

        begin
          desc = step_functions.describe_execution({
                                                    execution_arn: req.execution_arn
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
                                                    URL: 'https://dovetail.prxu.org/152/245d0fe2-4171-4ebf-bea3-69deff3e9336/input file with spaces.mp3'
                                                  },
                                                  Tasks: [
                                                    {
                                                      Type: 'Copy',
                                                      Mode: 'AWS/S3',
                                                      BucketName: CONFIG.PORTER_TEST_BUCKET_NAME,
                                                      ObjectKey: 'copied+file+with+spaces'
                                                    }
                                                  ]
                                                }
                                              }.to_json
                                            })

        max_retries = 60
        retries = 0

        begin
          desc = step_functions.describe_execution({
                                                    execution_arn: req.execution_arn
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
                                                    URL: 'https://dovetail.prxu.org/152/245d0fe2-4171-4ebf-bea3-69deff3e9336/input%20file%20with%20spaces.mp3'
                                                  },
                                                  Tasks: [
                                                    {
                                                      Type: 'Copy',
                                                      Mode: 'AWS/S3',
                                                      BucketName: CONFIG.PORTER_TEST_BUCKET_NAME,
                                                      ObjectKey: 'copied+file+with+spaces'
                                                    }
                                                  ]
                                                }
                                              }.to_json
                                            })

        max_retries = 60
        retries = 0

        begin
          desc = step_functions.describe_execution({
                                                    execution_arn: req.execution_arn
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
                                                    URL: 'https://dovetail.prxu.org/152/245d0fe2-4171-4ebf-bea3-69deff3e9336/input+file+with+spaces.mp3'
                                                  },
                                                  Tasks: [
                                                    {
                                                      Type: 'Copy',
                                                      Mode: 'AWS/S3',
                                                      BucketName: CONFIG.PORTER_TEST_BUCKET_NAME,
                                                      ObjectKey: 'copied+file+with+spaces'
                                                    }
                                                  ]
                                                }
                                              }.to_json
                                            })

        max_retries = 60
        retries = 0

        begin
          desc = step_functions.describe_execution({
                                                    execution_arn: req.execution_arn
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
                                                    URL: 'https://dovetail.prxu.org/152/245d0fe2-4171-4ebf-bea3-69deff3e9336/input%2Bfile%2Bwith%2Bspaces.mp3'
                                                  },
                                                  Tasks: [
                                                    {
                                                      Type: 'Copy',
                                                      Mode: 'AWS/S3',
                                                      BucketName: CONFIG.PORTER_TEST_BUCKET_NAME,
                                                      ObjectKey: 'copied+file+with+spaces'
                                                    }
                                                  ]
                                                }
                                              }.to_json
                                            })

        max_retries = 60
        retries = 0

        begin
          desc = step_functions.describe_execution({
                                                    execution_arn: req.execution_arn
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
                                                    URL: 'https://placeimg.com/5/5/input%25file%25with%25spaces'
                                                  },
                                                  Tasks: [
                                                    {
                                                      Type: 'Copy',
                                                      Mode: 'AWS/S3',
                                                      BucketName: CONFIG.PORTER_TEST_BUCKET_NAME,
                                                      ObjectKey: 'copied+file+with+spaces'
                                                    }
                                                  ]
                                                }
                                              }.to_json
                                            })

        max_retries = 60
        retries = 0

        begin
          desc = step_functions.describe_execution({
                                                    execution_arn: req.execution_arn
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
