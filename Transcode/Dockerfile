FROM jrottenberg/ffmpeg:4.1-alpine

RUN apk add -v --update --no-cache python3 && \
    pip3 install --upgrade pip setuptools && \
    pip3 install --upgrade --no-cache-dir awscli && \
    rm -rf /var/cache/apk/* && \
    rm -rf /tmp/* /var/tmp/*

ADD transcode.sh /transcode.sh
RUN chmod +x /transcode.sh

ENTRYPOINT ["/transcode.sh"]
