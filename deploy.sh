#!/bin/bash
set -e

if [ $1 = "prod" ]
then
        source ./.env.prod
else
        source ./.env.stag
fi

mkdir -p .deploy

# Check Versioning status for resources bucket
bucket_versioning=`aws s3api get-bucket-versioning --profile "$AWS_PROFILE" --bucket "$STACK_RESOURCES_BUCKET" --output text --query 'Status'`
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
        version_id=`aws s3api put-object --profile "$AWS_PROFILE" --bucket "$STACK_RESOURCES_BUCKET" --key "${CLOUDFORMATION_STACK_NAME}/lambdas/${dirname}.zip" --acl private --body ../../.deploy/lambdas/"$dirname".zip --output text --query 'VersionId'`
        declare "${dirname}_${version_suffix}"="$version_id"
        cd ..
done < <(find * -maxdepth 0 -type d)
cd ..

aws cloudformation deploy \
        --region "$AWS_DEFAULT_REGION" \
        --s3-bucket cf-templates-1r2sjvlu82hbi-us-east-1 \
        --template-file ./porter.yml \
        --profile "$AWS_PROFILE" \
        --stack-name "$CLOUDFORMATION_STACK_NAME" \
        --capabilities CAPABILITY_IAM \
        --notification-arns "$CFN_SNS_TOPIC" \
        --parameter-overrides \
                StackResourcesBucket="$STACK_RESOURCES_BUCKET" \
                AwsXraySdkLambdaLayerVersionArn=arn:aws:lambda:us-east-1:561178107736:layer:aws-xray:2 \
                FfmpegLambdaLayerVersionArn=arn:aws:lambda:us-east-1:561178107736:layer:bin-ffmpeg:1 \
                MpckLambdaLayerVersionArn=arn:aws:lambda:us-east-1:561178107736:layer:bin-mpck:1 \
                NpmSharpLambdaLayerVersionArn=arn:aws:lambda:us-east-1:561178107736:layer:npm-sharp:1 \
                NpmFileTypeLambdaLayerVersionArn=arn:aws:lambda:us-east-1:561178107736:layer:npm-file-type:1 \
                JobExecutionSnsTopicLambdaFunctionS3ObjectVersion="$JobExecutionSnsTopicLambdaFunction_S3ObjectVersion" \
                NormalizeInputLambdaFunctionS3ObjectVersion="$NormalizeInputLambdaFunction_S3ObjectVersion" \
                IngestLambdaFunctionS3ObjectVersion="$IngestLambdaFunction_S3ObjectVersion" \
                ImageTransformLambdaFunctionS3ObjectVersion="$ImageTransformLambdaFunction_S3ObjectVersion" \
                InspectMediaLambdaFunctionS3ObjectVersion="$InspectMediaLambdaFunction_S3ObjectVersion" \
                CopyLambdaFunctionS3ObjectVersion="$CopyLambdaFunction_S3ObjectVersion" \
                CallbackLambdaFunctionS3ObjectVersion="$CallbackLambdaFunction_S3ObjectVersion" \
                SourceTypeLambdaFunctionS3ObjectVersion="$SourceTypeLambdaFunction_S3ObjectVersion" \
                TranscodeEcsTaskDefinitionImage=561178107736.dkr.ecr.us-east-1.amazonaws.com/porter:latest \
                TaskDestinationBucketPolicyResources="$S3_BUCKET_POLICY_RESOURCES" \
                TaskDestinationObjectPolicyResources="$S3_OBJECT_POLICY_RESOURCES" \
                OpsWarnMessagesSnsTopicArn="$WARN_SNS_TOPIC" \
                OpsErrorMessagesSnsTopicArn="$ERROR_SNS_TOPIC"
