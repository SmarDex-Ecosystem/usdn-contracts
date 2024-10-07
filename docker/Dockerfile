FROM ghcr.io/foundry-rs/foundry:latest AS dev

WORKDIR /usr/app/

# Copy usdn-contracts to /usr/app/
COPY . .

# Add node 20 to foundry image
COPY --from=node:20-alpine /usr/lib /usr/lib
COPY --from=node:20-alpine /usr/local/share /usr/local/share
COPY --from=node:20-alpine /usr/local/lib /usr/local/lib
COPY --from=node:20-alpine /usr/local/include /usr/local/include
COPY --from=node:20-alpine /usr/local/bin /usr/local/bin


# Add bash and jq to foundry image
RUN apk add bash jq

# Install forge, soldeer, and npm
RUN forge soldeer install && \
    npm install

# Precompile contracts
RUN forge build src script

# Append dump command to deployFork.sh
RUN printf '\necho "$FORK_ENV_DUMP" > .env.fork' >> script/deployFork.sh
