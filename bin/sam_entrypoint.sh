#!/bin/bash
set -o errexit

# Credentials with access to pull down the Lambda Layers being passed in as
# parameters below
export AWS_ACCESS_KEY_ID=
export AWS_SECRET_ACCESS_KEY=

BASEDIR="$1"
/usr/local/bin/sam local start-lambda \
  --host 0.0.0.0 \
  --docker-volume-basedir "${BASEDIR}" \
  --docker-network porternetwork \
  --skip-pull-image \
  --region us-east-1 \
  --parameter-overrides \
    'AwsXraySdkLambdaLayerVersionArn="arn:aws:lambda:us-east-1:561178107736:layer:aws-xray:3"' \
    'NpmFileTypeLambdaLayerVersionArn=arn:aws:lambda:us-east-1:561178107736:layer:npm-file-type:2' \
    'FfmpegLambdaLayerVersionArn=arn:aws:lambda:us-east-1:561178107736:layer:bin-ffmpeg:1' \
    'MpckLambdaLayerVersionArn=arn:aws:lambda:us-east-1:561178107736:layer:bin-mpck:1' \
    'NpmSharpLambdaLayerVersionArn=arn:aws:lambda:us-east-1:561178107736:layer:npm-sharp:1'
