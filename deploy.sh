#!/bin/bash

aws cloudformation deploy \
        --region us-east-1 \
        --profile prx_legacy \
        --s3-bucket cf-templates-1r2sjvlu82hbi-us-east-1 \
        --template-file ./fixer-state-machine.yml \
        --stack-name fixer-state-machine-prototype \
        --capabilities CAPABILITY_IAM \
        --parameter-overrides \
                AwsXraySdkLambdaLayerVersionArn=arn:aws:lambda:us-east-1:561178107736:layer:aws-xray:1 \
                FfmepgLambdaLayerVersionArn=arn:aws:lambda:us-east-1:561178107736:layer:ffmepg-farski-test:1 \
                MpckLambdaLayerVersionArn=arn:aws:lambda:us-east-1:561178107736:layer:mpck-farski-test:1
