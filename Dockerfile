FROM jrottenberg/ffmpeg:4.1-alpine

RUN apk add -v --update --no-cache python3 && \
    pip3 install --upgrade pip setuptools && \
    pip3 install --upgrade --no-cache-dir awscli && \
    rm -rf /var/cache/apk/* && \
    rm -rf /tmp/* /var/tmp/*

# TODO This should run a script that Gets the job artifact from S3, processes
# it based on the job parameters, and sends the results back to S3

ENTRYPOINT ["ffmpeg", "-formats"]
