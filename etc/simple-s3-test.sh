#!/bin/bash

export AWS_PROFILE=prx_legacy
export AWS_DEFAULT_REGION=us-east-1

state_machine_arn="arn:aws:states:us-east-1:561178107736:stateMachine:StateMachine-cvPVX5enHWdj"

read -r -d '' input_json << EOM
    {
        "Job": {
            "Id": "1234567890asdfghjkl",
            "Source": {
                "Mode": "AWS/S3",
                "BucketName": "farski-sandbox-prx",
                "ObjectKey": "podcast.wav"
            }
        }
    }
EOM

aws stepfunctions start-execution --state-machine-arn "$state_machine_arn" --input "$input_json"
