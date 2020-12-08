require 'aws-sdk-s3'
require 'digest/sha2'
require 'tempfile'
require 'fileutils'
require 'logger'
load './utils.rb'

# This is a more paranoid s3 download class
# based on all the various errors that have been handled in fixer.
class S3Files
  include Utils
  attr_reader :s3, :logger, :retry_count

  def initialize(client = nil, logger = nil, retry_count = 10)
    @s3 = client || Aws::S3::Client.new
    @logger = logger || Logger.new(STDOUT)
    @retry_count = retry_count || ENV['S3_RETRY_COUNT']
  end

  def download_file(bucket, key)
    file_info = nil
    file_downloaded = false
    temp_file = nil

    # We saw timing errors where a file was saved to s3,
    # but didn't show up yet on get,
    # so we added retry/timeout to wait for it before fully failing the task.
    # This also allows us to get the content-length,
    # so that can be used later to see if the file has been fully downloaded.
    tries = 0
    while !file_info && tries < retry_count
      begin
        tries += 1
        file_info = s3.head_object(bucket: bucket, key: key)
      rescue Aws::S3::Errors::Forbidden => err
        logger.debug "head(#{tries}) '#{bucket}/#{key}' - #{err.message}"
      end
      sleep(1) if !file_info
    end
    raise "File not found on s3: '#{bucket}/#{key}'" if !file_info

    tries = 0
    while !file_downloaded && tries < retry_count
      tries += 1
      begin

        # in case a temp_file was partially written, start over
        if temp_file
          temp_file.close rescue nil
          File.unlink(temp_file) rescue nil
        end

        temp_file = create_temp_file(key.split('/').last)
        s3.get_object(bucket: bucket, key: key) do |chunk|
          temp_file.write(chunk)
        end

        temp_file.fsync

        if (file_info.content_length != temp_file.size)
          raise "File incorrect size, s3: '#{bucket}/#{key}' #{
                  file_info.content_length
                }, local: #{temp_file.size}"
        end

        file_downloaded = true
      rescue StandardError => err
        logger.error "File get failed: '#{bucket}/#{key}': #{err.message}"
      end
      sleep(1)
    end

    if (file_info.content_length != temp_file.size)
      raise "File get failed, bad size: '#{bucket}/#{key}' #{
              file_info.content_length}, local file size: #{
              temp_file.size
            }"
    end

    raise "Zero length file from s3: '#{bucket}/#{key}'" if temp_file.size == 0

    temp_file
  end
end
