#!/bin/bash

export AWS_PROFILE=prx_legacy
export AWS_DEFAULT_REGION=us-east-1

$(aws ecr get-login --no-include-email --region us-east-1)
docker build -t rexif-prototype .
docker tag rexif-prototype:latest 561178107736.dkr.ecr.us-east-1.amazonaws.com/rexif-prototype:latest
docker push 561178107736.dkr.ecr.us-east-1.amazonaws.com/rexif-prototype:latest
