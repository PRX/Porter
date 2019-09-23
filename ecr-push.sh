#!/bin/bash

$(aws ecr get-login --no-include-email --region us-east-2 --profile prx_it_services)
docker build -t sf-test .
docker tag sf-test:latest 127213743756.dkr.ecr.us-east-2.amazonaws.com/sf-test:latest
docker push 127213743756.dkr.ecr.us-east-2.amazonaws.com/sf-test:latest
