# FTP Container

## Getting Started
To try this out:
```
cp env-example .env
# edit .env with working values

# build it, and get ftpd started
docker-compose build
docker-compose up  --no-start
docker-compose start ftpd

# run ftp service to see a file transfer
docker-compose run ftp
```

## Testing
Needs to have a different entrypoint script besides `run` added to run tests.
Also, add tests.

In the meantime, tweak `.env` to create different conditions, then run `ftp`.

## ToDos
* Tests!
* ftps support
