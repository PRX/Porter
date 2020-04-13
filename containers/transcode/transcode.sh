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
# STATE_MACHINE_DESTINATION_BUCKET_NAME
# STATE_MACHINE_DESTINATION_OBJECT_KEY
# STATE_MACHINE_DESTINATION_PARAMETER_CONTENT_TYPE
# STATE_MACHINE_DESTINATION_FORMAT
# STATE_MACHINE_FFMPEG_GLOBAL_OPTIONS
# STATE_MACHINE_FFMPEG_INPUT_FILE_OPTIONS
# STATE_MACHINE_FFMPEG_OUTPUT_FILE_OPTIONS

start_time=`date +%s`

aws cloudwatch put-metric-data \
    --namespace "PRX/Porter" \
    --metric-name Transcodes \
    --unit Count \
    --value 1 \
    --dimensions "StateMachineName=$STATE_MACHINE_NAME"

# Get the artifact file from S3
aws s3 cp s3://"$STATE_MACHINE_ARTIFACT_BUCKET_NAME"/"$STATE_MACHINE_ARTIFACT_OBJECT_KEY" artifact

./ffmpeg-git-20200305-amd64-static/ffmpeg \
    $STATE_MACHINE_FFMPEG_GLOBAL_OPTIONS \
    $STATE_MACHINE_FFMPEG_INPUT_FILE_OPTIONS -i artifact \
    $STATE_MACHINE_FFMPEG_OUTPUT_FILE_OPTIONS -f $STATE_MACHINE_DESTINATION_FORMAT output

end_time=`date +%s`
duration=$((end_time-start_time))

aws cloudwatch put-metric-data \
    --namespace "PRX/Porter" \
    --metric-name TranscodeDuration \
    --unit Seconds \
    --value $duration \
    --dimensions "StateMachineName=$STATE_MACHINE_NAME"

# Assume a role that will have access to the S3 destination bucket, and use
# that roles credentials for the s3 cp call
role=$(aws sts assume-role --region "$STATE_MACHINE_AWS_REGION" --endpoint-url "https://sts.$STATE_MACHINE_AWS_REGION.amazonaws.com" --role-arn "$STATE_MACHINE_S3_DESTINATION_WRITER_ROLE" --role-session-name porter_transcode_task)
export AWS_ACCESS_KEY_ID=$(echo $role | jq -r .Credentials.AccessKeyId)
export AWS_SECRET_ACCESS_KEY=$(echo $role | jq -r .Credentials.SecretAccessKey)
export AWS_SESSION_TOKEN=$(echo $role | jq -r .Credentials.SessionToken)

aws s3 cp output s3://"$STATE_MACHINE_DESTINATION_BUCKET_NAME"/"$STATE_MACHINE_DESTINATION_OBJECT_KEY" --content-type "$STATE_MACHINE_DESTINATION_PARAMETER_CONTENT_TYPE"
