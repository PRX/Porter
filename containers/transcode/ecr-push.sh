#!/bin/bash

export AWS_PROFILE=prx-legacy
export AWS_DEFAULT_REGION=us-east-1

$(aws ecr get-login --no-include-email --region us-east-1)
docker build -t porter .
docker tag porter:latest 561178107736.dkr.ecr.us-east-1.amazonaws.com/porter:latest
docker push 561178107736.dkr.ecr.us-east-1.amazonaws.com/porter:latest
