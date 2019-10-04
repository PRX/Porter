FROM mhart/alpine-node:10.15.3 as test

WORKDIR /ci

ADD ./lambdas ./
ADD ./test/lambdas/package.json ./
RUN npm install

ADD ./test ./test

ENTRYPOINT [ "npm", "run" ]
CMD [ "test" ]
