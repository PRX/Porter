#!/bin/python

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

import boto3
import os
import json
import time

cloudwatch = boto3.client('cloudwatch')
s3 = boto3.resource('s3')

start_time = time.time()

# Count the transcode in CloudWatch Metrics
cloudwatch.put_metric_data(
    Namespace='PRX/Porter',
    MetricData=[
        {
            'MetricName': 'Transcodes',
            'Dimensions': [
                {
                    'Name': 'StateMachineName',
                    'Value': os.environ['STATE_MACHINE_NAME']
                }
            ],
            'Value': 1,
            'Unit': 'Count'
        }
    ]
)

# Get the artifact file from S3
print('Downloading artifact')
s3.meta.client.download_file(
    os.environ['STATE_MACHINE_ARTIFACT_BUCKET_NAME'],
    os.environ['STATE_MACHINE_ARTIFACT_OBJECT_KEY'],
    'artifact.file'
)

# Execute the transcode
ffmpeg_cmd = ' '.join([
    "./ffmpeg-git-20200504-amd64-static/ffmpeg",
    os.environ['STATE_MACHINE_FFMPEG_GLOBAL_OPTIONS'],
    "{i} -i artifact.file".format(
        i=os.environ['STATE_MACHINE_FFMPEG_INPUT_FILE_OPTIONS']
    ),
    "{o} -f {f} output.file".format(
        o=os.environ['STATE_MACHINE_FFMPEG_OUTPUT_FILE_OPTIONS'],
        f=os.environ['STATE_MACHINE_DESTINATION_FORMAT']
    )
])

print('Calling FFmpeg')
print(ffmpeg_cmd)

if os.system(ffmpeg_cmd) != 0:
    raise Exception('FFmpeg failed')

end_time = time.time()
duration = end_time - start_time

# Record transcode duration in CloudWatch Metrics
cloudwatch.put_metric_data(
    Namespace='PRX/Porter',
    MetricData=[
        {
            'MetricName': 'TranscodeDuration',
            'Dimensions': [
                {
                    'Name': 'StateMachineName',
                    'Value': os.environ['STATE_MACHINE_NAME']
                }
            ],
            'Value': duration,
            'Unit': 'Seconds'
        }
    ]
)

destination = json.loads(os.environ['STATE_MACHINE_DESTINATION_JSON'])

if destination['Mode'] == 'AWS/S3':
    region = os.environ['STATE_MACHINE_AWS_REGION']
    sts = boto3.client(
        'sts',
        endpoint_url="https://sts.{}.amazonaws.com".format(region)
    )

    # Assume a role that will have access to the S3 destination bucket, and use
    # that roles credentials for the S3 upload
    role = sts.assume_role(
        RoleArn=os.environ['STATE_MACHINE_S3_DESTINATION_WRITER_ROLE'],
        RoleSessionName='porter_transcode_task',
    )

    s3_writer = boto3.resource(
        's3',
        aws_access_key_id=role['Credentials']['AccessKeyId'],
        aws_secret_access_key=role['Credentials']['SecretAccessKey'],
        aws_session_token=role['Credentials']['SessionToken'],
    )

    s3_parameters = {}

    if 'Parameters' in destination:
        s3_parameters = destination['Parameters']

    # Upload the encoded file to the S3
    print('Writing output to S3 destination')
    s3_writer.meta.client.upload_file(
        'output.file',
        os.environ['STATE_MACHINE_DESTINATION_BUCKET_NAME'],
        os.environ['STATE_MACHINE_DESTINATION_OBJECT_KEY'],
        ExtraArgs=s3_parameters
    )
