FROM ghcr.io/foundry-rs/foundry:latest AS dev

WORKDIR /usr/app/

# Copy usdn-contracts needed files to /usr/app/
COPY script ./script
COPY src ./src
COPY test/utils/Sdex.sol test/utils/WstEth.sol ./test/utils/
COPY foundry.toml soldeer.lock \
    package.json package-lock.json \
    ./

# Add node 20 to foundry image
COPY --from=node:20-slim /usr/lib /usr/lib
COPY --from=node:20-slim /usr/local/share /usr/local/share
COPY --from=node:20-slim /usr/local/lib /usr/local/lib
COPY --from=node:20-slim /usr/local/include /usr/local/include
COPY --from=node:20-slim /usr/local/bin /usr/local/bin

# Add bash and jq to foundry image
RUN apt update && apt install bash jq -y

# Install forge, soldeer, and npm
RUN forge soldeer install && \
    npm install

# Precompile contracts
RUN forge build src script
# Append dump command to deployFork.sh
RUN printf '\necho "$FORK_ENV_DUMP" > .env.fork' >> script/deployFork.sh
