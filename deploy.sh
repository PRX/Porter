#!/bin/bash

aws cloudformation deploy \
        --region us-east-2 \
        --profile prx_it_services \
        --s3-bucket cf-templates-19dybi845jxs3-us-east-2 \
        --template-file ./fixer-state-machine.yml \
        --stack-name fixer-state-machine-prototype \
        --capabilities CAPABILITY_IAM \
        --parameter-overrides \
                AwsXraySdkLambdaLayerVersionArn=arn:aws:lambda:us-east-1:561178107736:layer:aws-xray:1 \
                FfmepgLambdaLayerVersionArn=arn:aws:lambda:us-east-1:561178107736:layer:ffmepg-farski-test:1 \
                MpckLambdaLayerVersionArn=arn:aws:lambda:us-east-1:561178107736:layer:mpck-farski-test:1
