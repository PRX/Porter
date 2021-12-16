# frozen_string_literal: true

require 'test_helper'
require 'json'

describe :porter do
  describe :copy do
    describe :to_key_with_spaces do
      it 'handles HTTP source files with spaces' do
        job = {
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
        }

        job_test(job) do |output|
          _(output['JobResult']['Job']['Id']).must_equal 'porter-test-copy-http-spaces-to-spaces'
          _(output['JobResult']['State']).must_equal 'DONE'
          _(output['JobResult']['FailedTasks']).must_equal []
          _(output['JobResult']['TaskResults'].length).must_equal 1
        end
      end

      it 'handles HTTP source files with encoded spaces' do
        job = {
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
        }

        job_test(job) do |output|
          _(output['JobResult']['Job']['Id']).must_equal 'porter-test-copy-http-encoded-spaces-to-spaces'
          _(output['JobResult']['State']).must_equal 'DONE'
          _(output['JobResult']['FailedTasks']).must_equal []
          _(output['JobResult']['TaskResults'].length).must_equal 1
        end
      end

      it 'handles HTTP source files with plus' do
        job = {
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
        }

        job_test(job) do |output|
          _(output['JobResult']['Job']['Id']).must_equal 'porter-test-copy-http-plus-to-spaces'
          _(output['JobResult']['State']).must_equal 'DONE'
          _(output['JobResult']['FailedTasks']).must_equal []
          _(output['JobResult']['TaskResults'].length).must_equal 1
        end
      end

      it 'handles HTTP source files with encoded plus' do
        job = {
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
        }

        job_test(job) do |output|
          _(output['JobResult']['Job']['Id']).must_equal 'porter-test-copy-http-encoded-plus-to-spaces'
          _(output['JobResult']['State']).must_equal 'DONE'
          _(output['JobResult']['FailedTasks']).must_equal []
          _(output['JobResult']['TaskResults'].length).must_equal 1
        end
      end

      it 'handles HTTP source files with encoded percent' do
        job = {
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
        }

        job_test(job) do |output|
          _(output['JobResult']['Job']['Id']).must_equal 'porter-test-copy-http-encoded-percent-to-spaces'
          _(output['JobResult']['State']).must_equal 'DONE'
          _(output['JobResult']['FailedTasks']).must_equal []
          _(output['JobResult']['TaskResults'].length).must_equal 1
        end
      end
    end

    describe :to_key_with_plus do
      it 'handles HTTP source files with spaces' do
        job = {
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
        }

        job_test(job) do |output|
          _(output['JobResult']['Job']['Id']).must_equal 'porter-test-copy-http-spaces-to-plus'
          _(output['JobResult']['State']).must_equal 'DONE'
          _(output['JobResult']['FailedTasks']).must_equal []
          _(output['JobResult']['TaskResults'].length).must_equal 1
        end
      end

      it 'handles HTTP source files with encoded spaces' do
        job = {
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
        }

        job_test(job) do |output|
          _(output['JobResult']['Job']['Id']).must_equal 'porter-test-copy-http-encoded-spaces-to-plus'
          _(output['JobResult']['State']).must_equal 'DONE'
          _(output['JobResult']['FailedTasks']).must_equal []
          _(output['JobResult']['TaskResults'].length).must_equal 1
        end
      end

      it 'handles HTTP source files with plus' do
        job = {
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
        }
        job_test(job) do |output|
          _(output['JobResult']['Job']['Id']).must_equal 'porter-test-copy-http-plus-to-plus'
          _(output['JobResult']['State']).must_equal 'DONE'
          _(output['JobResult']['FailedTasks']).must_equal []
          _(output['JobResult']['TaskResults'].length).must_equal 1
        end
      end

      it 'handles HTTP source files with encoded plus' do
        job = {
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
        }

        job_test(job) do |output|
          _(output['JobResult']['Job']['Id']).must_equal 'porter-test-copy-http-encoded-plus-to-plus'
          _(output['JobResult']['State']).must_equal 'DONE'
          _(output['JobResult']['FailedTasks']).must_equal []
          _(output['JobResult']['TaskResults'].length).must_equal 1
        end
      end

      it 'handles HTTP source files with encoded percent' do
        job = {
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
        }

        job_test(job) do |output|
          _(output['JobResult']['Job']['Id']).must_equal 'porter-test-copy-http-encoded-percent-to-plus'
          _(output['JobResult']['State']).must_equal 'DONE'
          _(output['JobResult']['FailedTasks']).must_equal []
          _(output['JobResult']['TaskResults'].length).must_equal 1
        end
      end
    end
  end
end
