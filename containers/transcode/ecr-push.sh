#!/bin/bash

export AWS_PROFILE=prx-legacy

account_id=`aws sts get-caller-identity --output text --query 'Account'`

aws ecr get-login-password --region us-east-1 | docker login --username AWS --password-stdin "$account_id.dkr.ecr.us-east-1.amazonaws.com"
docker build -t porter .
docker tag porter:latest "$account_id.dkr.ecr.us-east-1.amazonaws.com/porter:latest"
docker push "$account_id.dkr.ecr.us-east-1.amazonaws.com/porter:latest"
