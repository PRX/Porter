require "aws-sdk-sts"

def send_to_s3(filename)
  region = ENV["STATE_MACHINE_AWS_REGION"]
  destination = JSON.parse(ENV["STATE_MACHINE_DESTINATION_JSON"])

  sts = Aws::STS::Client.new(endpoint: "https://sts.#{region}.amazonaws.com")

  # Assume a role that will have access to the S3 destination bucket, and use
  # that role's credentials for the S3 upload
  role = sts.assume_role({
    role_arn: ENV["STATE_MACHINE_S3_DESTINATION_WRITER_ROLE"],
    role_session_name: "porter_hls_task"
  })

  credentials = Aws::Credentials.new(
    role.credentials.access_key_id,
    role.credentials.secret_access_key,
    role.credentials.session_token
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
    s3_writer = Aws::S3::Client.new(credentials: credentials, endpoint: "https://s3.amazonaws.com")
    bucket_head = s3_writer.head_bucket({bucket: ENV["STATE_MACHINE_DESTINATION_BUCKET_NAME"]})
    bucket_region = bucket_head.context.http_response.headers["x-amz-bucket-region"]
  rescue Aws::S3::Errors::Http301Error, Aws::S3::Errors::PermanentRedirect => e
    bucket_region = e.context.http_response.headers["x-amz-bucket-region"]
  end

  puts "Destination bucket in region: #{bucket_region}"

  # Create a new client with the permissions and the correct region
  s3_writer = Aws::S3::Client.new(credentials: credentials, region: bucket_region)

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
  put_object_params[:key] = [ENV["STATE_MACHINE_DESTINATION_OBJECT_KEY_PREFIX"], filename].join

  puts "Destination object key: #{put_object_params[:key]}"

  # For now, we force the content-type of all files, in sort of a naive way
  put_object_params[:content_type] = filename.end_with?(".ts") ? "video/mp2t" : "application/vnd.apple.mpegurl"

  # Upload the encoded file to the S3
  puts "Writing output to S3 destination"
  put_ouput_s3tm = Aws::S3::TransferManager.new(client: s3_writer)
  put_ouput_s3tm.upload_file(filename, **put_object_params)
end
