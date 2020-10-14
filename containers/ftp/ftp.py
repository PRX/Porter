#!/bin/python

# The following environment variables are passed in as ContainerOverrides when
# the state machine runs the ECS task
# STATE_MACHINE_NAME
# STATE_MACHINE_EXECUTION_ID
# STATE_MACHINE_JOB_ID
# STATE_MACHINE_TASK_INDEX
# STATE_MACHINE_AWS_REGION
# STATE_MACHINE_ARTIFACT_BUCKET_NAME
# STATE_MACHINE_ARTIFACT_OBJECT_KEY
# STATE_MACHINE_TASK_JSON

import boto3
import os
import json
import time
from ftplib import FTP
from urlparse import urlparse

cloudwatch = boto3.client('cloudwatch')
s3 = boto3.resource('s3')

start_time = time.time()

# Count the transfers in CloudWatch Metrics
cloudwatch.put_metric_data(
    Namespace='PRX/Porter',
    MetricData=[
        {
            'MetricName': 'FtpTransfers',
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

task = json.loads(os.environ['STATE_MACHINE_TASK_JSON'])
uri = urlparse(task['URL'])

ftp_filename = os.path.split(uri.path)[1]
ftp = FTP(host=uri.hostname, user=uri.username, passwd=uri.password)
ftp.storbinary('STOR ' + ftp_filename, open('artifact.file', 'rb'))
ftp.quit()

end_time = time.time()
duration = end_time - start_time

# Record transfer duration in CloudWatch Metrics
cloudwatch.put_metric_data(
    Namespace='PRX/Porter',
    MetricData=[
        {
            'MetricName': 'FtpTransferDuration',
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
