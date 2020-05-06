FROM mhart/alpine-node:10.15.3 as test

ENV APP_HOME /app
ENV HOME=$APP_HOME
RUN mkdir -p $APP_HOME
WORKDIR $APP_HOME

ADD ./package.json ./
RUN npm install

ADD . ./

ENTRYPOINT [ "npm", "run" ]
