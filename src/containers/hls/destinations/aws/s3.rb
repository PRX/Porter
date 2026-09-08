require "aws-sdk-sts"

# should handle all the file extension => content types used by this hls task
# (e.g. doesn't include fmp4 related files, since we're not doing those yet)
CONTENT_TYPES = {
  ".ts" => "video/mp2t",
  ".m3u8" => "application/vnd.apple.mpegurl",
  ".m4s" => "video/iso.segment",
  ".mp4" => "video/mp4"
}.freeze
DEFAULT_CONTENT_TYPE = "application/octet-stream"

# just this from ActiveSupport, no need to bring the whole gem in for one method.
# TODO: transcode.rb has this too, maybe refactor to a shared util?
class String
  def underscore
    gsub("::", "/")
      .gsub(/([A-Z]+)([A-Z][a-z])/, '\1_\2')
      .gsub(/([a-z\d])([A-Z])/, '\1_\2')
      .tr("-", "_")
      .downcase
  end
end

# destination role and detecting bucket region are per-upload, can memoize and reuse
# (i.e. for HLS, we need to write multiple files, not so much for other Porter tasks)
def s3_destination_writer
  @s3_destination_writer ||= begin
    region = ENV["STATE_MACHINE_AWS_REGION"]

    sts = Aws::STS::Client.new(endpoint: "https://sts.#{region}.amazonaws.com")

    # Assume a role that will have access to the S3 destination bucket, and use
    # that role's credentials for the S3 upload
    # `Aws::AssumeRoleCredentials` refreshes itself (if needed).
    credentials = Aws::AssumeRoleCredentials.new(
      client: sts,
      role_arn: ENV["STATE_MACHINE_S3_DESTINATION_WRITER_ROLE"],
      role_session_name: "porter_hls_task"
    )

    # The Ruby AWS SDK does not intelligently handle cases where the client isn't
    # explicitly set for the region where the bucket exists. We have to detect
    # the region using HeadBucket, and then create the client with the returned
    # region.
    # TODO This isn't necessary when the bucket and the client are in the same
    # region. It would be possible to catch the error and do the lookup only when
    # necessary.

    # Create a client with permission to HeadBucket
    begin
      probe = Aws::S3::Client.new(credentials: credentials, endpoint: "https://s3.amazonaws.com")
      head = probe.head_bucket({bucket: ENV["STATE_MACHINE_DESTINATION_BUCKET_NAME"]})
      bucket_region = head.context.http_response.headers["x-amz-bucket-region"]
    rescue Aws::S3::Errors::Http301Error, Aws::S3::Errors::PermanentRedirect => e
      bucket_region = e.context.http_response.headers["x-amz-bucket-region"]
    end

    puts "Destination bucket in region: #{bucket_region}"

    # Create a new client with the permissions and the correct region
    Aws::S3::Client.new(credentials: credentials, region: bucket_region)
  end
end

# single_file means every rendition is one object, so they all land in the same
# destination dir. hls.rb writes them under a work dir, so the local path and the
# object name diverge -- object_name defaults to the basename.
def send_to_s3(path, object_name = nil)
  object_name ||= File.basename(path)
  destination = JSON.parse(ENV["STATE_MACHINE_DESTINATION_JSON"])

  put_object_params = {}

  # For historical reasons, the available parameters match ALLOWED_UPLOAD_ARGS
  # from Boto3's S3Transfer class.
  # https://boto3.amazonaws.com/v1/documentation/api/latest/reference/customizations/s3.html
  # If any parameters are included on the destination config, they are
  # reformatted to snake case, and added to the put_object params as symbols.
  if destination.key?("Parameters")
    destination["Parameters"].each do |k, v|
      put_object_params[k.underscore.to_sym] = v
    end
  end

  put_object_params[:bucket] = ENV["STATE_MACHINE_DESTINATION_BUCKET_NAME"]
  put_object_params[:key] = [ENV["STATE_MACHINE_DESTINATION_OBJECT_KEY_PREFIX"], object_name].join

  puts "Destination object key: #{put_object_params[:key]}"

  # look up the content type based on the file extension, default to octet-stream if unknown
  put_object_params[:content_type] = CONTENT_TYPES.fetch(File.extname(object_name), DEFAULT_CONTENT_TYPE)

  # Upload the encoded file to the S3
  puts "Writing output to S3 destination"
  put_ouput_s3tm = Aws::S3::TransferManager.new(client: s3_destination_writer)
  put_ouput_s3tm.upload_file(path, **put_object_params)
end
