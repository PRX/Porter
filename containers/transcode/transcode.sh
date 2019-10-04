#!/bin/bash
set -e

# The following environment variables are passed in as ContainerOverrides when
# the state machine runs the ECS task
# STATE_MACHINE_EXECUTION_ID
# STATE_MACHINE_ARTIFACT_BUCKET_NAME
# STATE_MACHINE_ARTIFACT_OBJECT_KEY
# STATE_MACHINE_DESTINATION_BUCKET_NAME
# STATE_MACHINE_DESTINATION_OBJECT_KEY
# STATE_MACHINE_DESTINATION_FORMAT
# STATE_MACHINE_JOB_ID

# Get the artifact file from S3
aws s3 cp s3://"$STATE_MACHINE_ARTIFACT_BUCKET_NAME"/"$STATE_MACHINE_ARTIFACT_OBJECT_KEY" artifact

./ffmpeg-git-20190922-amd64-static/ffmpeg -loglevel info -i artifact -f "$STATE_MACHINE_DESTINATION_FORMAT" output

aws s3 cp output s3://"$STATE_MACHINE_DESTINATION_BUCKET_NAME"/"$STATE_MACHINE_DESTINATION_OBJECT_KEY"