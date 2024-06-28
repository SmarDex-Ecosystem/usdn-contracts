# Node 20 LTS at this time
ARG NODE_VERSION=20.15.0

FROM node:${NODE_VERSION}-alpine AS node


# Exceptional nightly build usage as we need some fixes that are not yet in the stable release
FROM ghcr.io/foundry-rs/foundry:nightly-7bef9caccfe62761225be66e84bea2810e656c96

# Fork env
ENV FORK_CODE_LIMIT=100000
ENV FORK_BLOCK_TIME=12
ENV FORK_PORT=8545
ENV FORK_URL=https://eth-mainnet.g.alchemy.com/v2/ZMTGh2wcbFIUDheXaKBN7cFHBfccH-RT
ENV FORK_CHAIN_ID=31337

ENV PNPM_HOME="/pnpm"
ENV PATH="$PNPM_HOME:$PATH"

# Import node into our foundry image
COPY --from=node /usr/lib /usr/lib
COPY --from=node /usr/local/lib /usr/local/lib
COPY --from=node /usr/local/include /usr/local/include
COPY --from=node /usr/local/bin /usr/local/bin

WORKDIR /opt/contracts

# Copy package management files
COPY ./package.json ./package.json
COPY ./Cargo.toml ./Cargo.toml
COPY ./foundry.toml ./foundry.toml
# Copy source files and scripts
COPY ./script/Deploy.s.sol ./script/Deploy.s.sol
COPY ./script/deployForkDocker.sh ./script/deployFork.sh
COPY ./src ./src
COPY ./test ./test
COPY ./lib ./lib
COPY .gitmodules ./.gitmodules

# Install dependencies
RUN apk add jq
# Forge requires to be in a git repository
RUN git init
RUN forge install

# Use pnpm to speed up deps installation
# Npm ~ 453.4s
# Pnpm ~ 19.7s
RUN wget -qO- https://get.pnpm.io/install.sh | ENV="$HOME/.shrc" SHELL="$(which sh)" sh -
RUN source ~/.shrc

RUN pnpm install

# Run node and deploy contracts
RUN nohup /bin/sh -c "anvil --code-size-limit $FORK_CODE_LIMIT --block-time $FORK_BLOCK_TIME --host 0.0.0.0 --port $FORK_PORT --fork-url $FORK_URL --state state.json --state-interval 12 --auto-impersonate --chain-id $FORK_CHAIN_ID &" && sleep 10 && ./script/deployFork.sh

RUN echo $(($(jq -r '[.blocks[] | { number: .header.number }] | sort_by(.number) | .[0].number' state.json)-1))

# Note command: $(($(jq -r '[.blocks[] | { number: .header.number }] | sort_by(.number) | .[0].number' state.json)-1))
# This command will get the last block number before the dump (state.json)
# It is necessary to fork until this block number to prevent state to conflict with mainnet fork resulting in a node blocks mismatch and crashs
ENTRYPOINT ["/bin/sh", "-c", "anvil -a 100 --host 0.0.0.0 --port ${FORK_PORT:-8545} --fork-url ${FORK_URL:-https://1rpc.io/eth} --state state.json --auto-impersonate --block-time ${FORK_BLOCK_TIME:-12} --state-interval ${FORK_BLOCK_TIME:-12} --chain-id 31337 --code-size-limit 100000 --fork-block-number $(($(jq -r '[.blocks[] | { number: .header.number }] | sort_by(.number) | .[0].number' state.json)-1))"]
