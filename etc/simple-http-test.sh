#!/bin/bash

export AWS_PROFILE=prx_legacy
export AWS_DEFAULT_REGION=us-east-1

state_machine_arn="arn:aws:states:us-east-1:561178107736:stateMachine:StateMachine-cvPVX5enHWdj"

read -r -d '' input_json << EOM
    {
        "Job": {
            "Id": "1234567890asdfghjkl",
            "Source": {
                "Mode": "HTTP",
                "URL": "https://dts.podtrac.com/redirect.mp3/dovetail.prxu.org/232/fbd26e97-dd82-48b8-9600-d8838f9f1dd4/Passenger_List_EP04_SEG_A.mp3"
            }
        }
    }
EOM

aws stepfunctions start-execution --state-machine-arn "$state_machine_arn" --input "$input_json"
