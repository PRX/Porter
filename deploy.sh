#!/bin/bash
set -e

mkdir -p .deploy

export AWS_PROFILE=prx_legacy
export AWS_DEFAULT_REGION=us-east-1

export STACK_RESOURCES_BUCKET=farski-sandbox-prx
export CLOUDFORMATION_STACK_NAME=fixer-state-machine-prototype

# Check Versioning status for resources bucket
bucket_versioning=`aws s3api get-bucket-versioning --bucket "$STACK_RESOURCES_BUCKET" --output text --query 'Status'`
if [ "$bucket_versioning" != "Enabled" ]
then
        echo "Bucket versioning must be enabled for the stack resources bucket"
        return 1
fi

# Copy Lambda code to S3
version_suffix="S3ObjectVersion"
mkdir -p .deploy/lambdas
cd ./lambdas
while read dirname
do
        cd "$dirname"
        zip -r "$dirname" *
        mv "${dirname}.zip" ../../.deploy/lambdas
        version_id=`aws s3api put-object --bucket "$STACK_RESOURCES_BUCKET" --key "${CLOUDFORMATION_STACK_NAME}/lambdas/${dirname}.zip" --acl private --body ../../.deploy/lambdas/"$dirname".zip --output text --query 'VersionId'`
        declare "${dirname}_${version_suffix}"="$version_id"
        cd ..
done < <(find * -maxdepth 0 -type d)
cd ..

aws cloudformation deploy \
        --region us-east-1 \
        --s3-bucket cf-templates-1r2sjvlu82hbi-us-east-1 \
        --template-file ./porter.yml \
        --stack-name "$CLOUDFORMATION_STACK_NAME" \
        --capabilities CAPABILITY_IAM \
        --parameter-overrides \
                StackResourcesBucket="$STACK_RESOURCES_BUCKET" \
                AwsXraySdkLambdaLayerVersionArn=arn:aws:lambda:us-east-1:561178107736:layer:aws-xray:2 \
                FfmepgLambdaLayerVersionArn=arn:aws:lambda:us-east-1:561178107736:layer:ffmepg-farski-test:1 \
                MpckLambdaLayerVersionArn=arn:aws:lambda:us-east-1:561178107736:layer:mpck-farski-test:1 \
                JobExecutionSnsTopicLambdaFunctionS3ObjectVersion="$JobExecutionSnsTopicLambdaFunction_S3ObjectVersion" \
                NormalizeInputLambdaFunctionS3ObjectVersion="$NormalizeInputLambdaFunction_S3ObjectVersion" \
                IngestLambdaFunctionS3ObjectVersion="$IngestLambdaFunction_S3ObjectVersion" \
                InspectMediaLambdaFunctionS3ObjectVersion="$InspectMediaLambdaFunction_S3ObjectVersion" \
                CopyLambdaFunctionS3ObjectVersion="$CopyLambdaFunction_S3ObjectVersion" \
                JobCallbackLambdaFunctionS3ObjectVersion="$JobCallbackLambdaFunction_S3ObjectVersion" \
                SourceTypeLambdaFunctionS3ObjectVersion="$SourceTypeLambdaFunction_S3ObjectVersion" \
                TranscodeEcsTaskDefinitionImage=561178107736.dkr.ecr.us-east-1.amazonaws.com/rexif-prototype:latest \
                TaskDestinationBucketPolicyResources=arn:aws:s3:::farski-sandbox-prx,arn:aws:s3:::staging-prx-feed,arn:aws:s3:::prx-ryan \
                TaskDestinationObjectPolicyResources=arn:aws:s3:::farski-sandbox-prx/*,arn:aws:s3:::staging-prx-feed/*,arn:aws:s3:::prx-ryan/* \
                OpsWarnMessagesSnsTopicArn=arn:aws:sns:us-east-1:561178107736:infrastructure-notifications-OpsWarnMessagesSnsTopic-1F2NNQY5K8YE \
                OpsErrorMessagesSnsTopicArn=arn:aws:sns:us-east-1:561178107736:infrastructure-notifications-OpsErrorMessagesSnsTopic-A4U0VVXEKBIL
