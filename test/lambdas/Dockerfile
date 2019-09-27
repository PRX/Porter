FROM mhart/alpine-node:10.15.3 as test

WORKDIR /ci

ADD ./package.json ./
RUN npm install

ADD . .

ENTRYPOINT [ "npm", "run" ]
CMD [ "test" ]
