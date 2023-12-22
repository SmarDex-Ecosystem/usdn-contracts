# Chainlink data streams setup

To setup the chainlink data streams, we need to have a StreamsUpkeep and a LogEmitter deployed contracts.

## Architecture

![Architecture](./architecture.png)
The Middleware contract will log an event that will be triggered by the Chainlink DON.
Then the chain link network will call our StreamsUpkeep with the price data.

## Register the upkeep
Register a new Log Trigger upkeep. See Automation Log Triggers to learn more about how to register Log Trigger upkeeps.

- Go to the [Chainlink Automation UI](https://automation.chain.link/) and connect your browser wallet.
- Click Register new Upkeep.
- Select the Log Trigger upkeep type and click Next.
- Specify a name for the upkeep.
- Specify the StreamsUpkeep contract address.
- Specify the emitter. This tells Chainlink Automation what contracts to watch for log triggers.
- Specify a Starting balance of 1 LINK for example.
- Leave the Check data value and other fields blank and Register the Upkeep.