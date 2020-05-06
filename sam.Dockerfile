FROM python:alpine

RUN apk update && \
    apk upgrade && \
    apk add bash && \
    apk add --no-cache --virtual build-deps build-base gcc && \
    pip install aws-sam-cli && \
    apk del build-deps

ENV APP_HOME /app
ENV HOME=$APP_HOME
RUN mkdir -p $APP_HOME
WORKDIR $APP_HOME

EXPOSE 3001

ENTRYPOINT ["./bin/sam_entrypoint.sh"]
