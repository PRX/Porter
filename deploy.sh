#!/bin/bash

aws cloudformation deploy \
        --region us-east-2 \
        --profile prx_it_services \
        --s3-bucket cf-templates-19dybi845jxs3-us-east-2 \
        --template-file ./fixer-state-machine.yml \
        --stack-name fixer-state-machine-prototype \
        --capabilities CAPABILITY_IAM \
        --parameter-overrides \
                AwsXraySdkLambdaLayerVersionArn=arn:aws:lambda:us-east-2:127213743756:layer:aws-xray-sdk:1 \
                FfmepgLambdaLayerVersionArn=arn:aws:lambda:us-east-2:127213743756:layer:ffmpeg:1
