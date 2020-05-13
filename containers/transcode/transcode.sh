#!/bin/bash

# The following environment variables are passed in as ContainerOverrides when
# the state machine runs the ECS task
# STATE_MACHINE_NAME
# STATE_MACHINE_EXECUTION_ID
# STATE_MACHINE_JOB_ID
# STATE_MACHINE_TASK_INDEX
# STATE_MACHINE_S3_DESTINATION_WRITER_ROLE
# STATE_MACHINE_AWS_REGION
# STATE_MACHINE_ARTIFACT_BUCKET_NAME
# STATE_MACHINE_ARTIFACT_OBJECT_KEY
# STATE_MACHINE_DESTINATION_MODE
# STATE_MACHINE_DESTINATION_FORMAT
# STATE_MACHINE_DESTINATION_JSON
# STATE_MACHINE_FFMPEG_GLOBAL_OPTIONS
# STATE_MACHINE_FFMPEG_INPUT_FILE_OPTIONS
# STATE_MACHINE_FFMPEG_OUTPUT_FILE_OPTIONS

start_time=`date +%s`

# Count the transcode in CloudWatch Metrics
aws cloudwatch put-metric-data \
  --namespace "PRX/Porter" \
  --metric-name Transcodes \
  --unit Count \
  --value 1 \
  --dimensions "StateMachineName=$STATE_MACHINE_NAME"

# Get the artifact file from S3
aws s3 cp s3://"$STATE_MACHINE_ARTIFACT_BUCKET_NAME"/"$STATE_MACHINE_ARTIFACT_OBJECT_KEY" artifact

# Execute the transcode
./ffmpeg-git-20200324-amd64-static/ffmpeg \
  $STATE_MACHINE_FFMPEG_GLOBAL_OPTIONS \
  $STATE_MACHINE_FFMPEG_INPUT_FILE_OPTIONS -i artifact \
  $STATE_MACHINE_FFMPEG_OUTPUT_FILE_OPTIONS -f $STATE_MACHINE_DESTINATION_FORMAT output

end_time=`date +%s`
duration=$((end_time-start_time))

# Record transcode duration in CloudWatch Metrics
aws cloudwatch put-metric-data \
  --namespace "PRX/Porter" \
  --metric-name TranscodeDuration \
  --unit Seconds \
  --value "$duration" \
  --dimensions "StateMachineName=$STATE_MACHINE_NAME"

destination_mode=`echo "$STATE_MACHINE_DESTINATION_JSON" | jq '.Mode'`

if [[ "$destination_mode" == "AWS/S3" ]]; then
  # Assume a role that will have access to the S3 destination bucket, and use
  # that roles credentials for the `s3 cp` call
  role=$(aws sts assume-role --region "$STATE_MACHINE_AWS_REGION" --endpoint-url "https://sts.$STATE_MACHINE_AWS_REGION.amazonaws.com" --role-arn "$STATE_MACHINE_S3_DESTINATION_WRITER_ROLE" --role-session-name porter_transcode_task)
  export AWS_ACCESS_KEY_ID=$(echo $role | jq -r .Credentials.AccessKeyId)
  export AWS_SECRET_ACCESS_KEY=$(echo $role | jq -r .Credentials.SecretAccessKey)
  export AWS_SESSION_TOKEN=$(echo $role | jq -r .Credentials.SessionToken)

  # Construct additional options to pass
  opts=""

  if [ $(echo $STATE_MACHINE_DESTINATION_JSON | jq '.Parameters.ACL') != "null" ]; then
    acl=`echo "$STATE_MACHINE_DESTINATION_JSON" | jq -r '.Parameters.ACL'`
    opts+=" --acl $acl"
  fi

  if [ $(echo $STATE_MACHINE_DESTINATION_JSON | jq '.Parameters.CacheControl') != "null" ]; then
    cache_control=`echo "$STATE_MACHINE_DESTINATION_JSON" | jq -r '.Parameters.CacheControl'`
    opts+=" --cache-control $cache_control"
  fi

  if [ $(echo $STATE_MACHINE_DESTINATION_JSON | jq '.Parameters.ContentDisposition') != "null" ]; then
    content_disposition=`echo "$STATE_MACHINE_DESTINATION_JSON" | jq -r '.Parameters.ContentDisposition'`
    opts+=" --content-disposition $content_disposition"
  fi

  if [ $(echo $STATE_MACHINE_DESTINATION_JSON | jq '.Parameters.ContentEncoding') != "null" ]; then
    content_encoding=`echo "$STATE_MACHINE_DESTINATION_JSON" | jq -r '.Parameters.ContentEncoding'`
    opts+=" --content-encoding $content_encoding"
  fi

  if [ $(echo $STATE_MACHINE_DESTINATION_JSON | jq '.Parameters.ContentLanguage') != "null" ]; then
    content_language=`echo "$STATE_MACHINE_DESTINATION_JSON" | jq -r '.Parameters.ContentLanguage'`
    opts+=" --content-language $content_language"
  fi

  if [ $(echo $STATE_MACHINE_DESTINATION_JSON | jq '.Parameters.ContentType') != "null" ]; then
    content_type=`echo "$STATE_MACHINE_DESTINATION_JSON" | jq -r '.Parameters.ContentType'`
    opts+=" --content-type $content_type"
  fi

  echo "$opts"

  aws s3 cp \
    output \
    s3://"$STATE_MACHINE_DESTINATION_BUCKET_NAME"/"$STATE_MACHINE_DESTINATION_OBJECT_KEY" \
    $opts
fi
