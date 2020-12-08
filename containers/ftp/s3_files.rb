require 'aws-sdk-s3'
require 'digest/sha2'
require 'tempfile'
require 'fileutils'
require 'logger'
load './utils.rb'

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
        if temp_file
          begin
            temp_file.close
          rescue StandardError
            nil
          end
          begin
            File.unlink(temp_file)
          rescue StandardError
            nil
          end
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
