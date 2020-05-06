FROM mhart/alpine-node:10.15.3 as test

ENV APP_HOME /app
ENV HOME=$APP_HOME
RUN mkdir -p $APP_HOME
WORKDIR $APP_HOME

RUN npm install

ENTRYPOINT [ "npm", "run" ]
