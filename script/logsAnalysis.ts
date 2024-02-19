import { Command } from 'commander';
import { DateTime } from 'luxon';
import pc from 'picocolors';
import { http, createTestClient, defineChain, formatEther, isAddressEqual, publicActions } from 'viem';
import { OracleMiddlewareAbi, UsdnAbi, UsdnProtocolAbi } from '../dist/abi';

function parseArgs() {
  const program = new Command();

  program
    .description('Retrieve and display all logs from a fork')
    .option(
      '-p, --protocol <address>',
      'address of the USDN protocol contract',
      '0x24EcC5E6EaA700368B8FAC259d3fBD045f695A08',
    )
    .option('-u, --usdn <address>', 'address of the USDN token contract', '0x0D92d35D311E54aB8EEA0394d7E773Fc5144491a')
    .option(
      '-m, --middleware <address>',
      'address of the oracle middleware contract',
      '0x4278C5d322aB92F1D876Dd7Bd9b44d1748b88af2',
    )
    .option('-r, --rpc-url <url>', 'URL of the RPC node to connect to')
    .parse(process.argv);

  return program.opts();
}

function getClient(rpcUrl: string) {
  const foundry = defineChain({
    id: 31_337,
    name: 'Foundry',
    nativeCurrency: {
      decimals: 18,
      name: 'Ether',
      symbol: 'ETH',
    },
    rpcUrls: {
      default: {
        http: [rpcUrl],
        webSocket: ['ws://127.0.0.1:8545'],
      },
    },
  });

  const client = createTestClient({
    chain: foundry,
    mode: 'anvil',
    transport: http(),
  }).extend(publicActions);

  return client;
}

async function main() {
  const options = parseArgs();

  if (!options.rpcUrl) {
    console.error('Please specify the RPC URL');
    process.exit(1);
  }

  const client = getClient(options.rpcUrl);

  const protocolEvents = UsdnProtocolAbi.filter((item) => item.type === 'event');
  const usdnEvents = UsdnAbi.filter((item) => item.type === 'event');
  const middlewareEvents = OracleMiddlewareAbi.filter((item) => item.type === 'event');

  const protocolLogs = await client.getLogs({
    address: options.protocol,
    events: protocolEvents,
    fromBlock: 0n,
  });
  const usdnLogs = await client.getLogs({
    address: options.usdn,
    events: usdnEvents,
    fromBlock: 0n,
  });
  const middlewareLogs = await client.getLogs({
    address: options.middleware,
    events: middlewareEvents,
    fromBlock: 0n,
  });

  const logs = [...protocolLogs, ...usdnLogs, ...middlewareLogs];
  logs.sort((a, b) => {
    const blockDiff = a.blockNumber - b.blockNumber;
    if (blockDiff === 0n) {
      return a.logIndex - b.logIndex;
    }
    return Number(blockDiff);
  });

  for (const log of logs) {
    console.log(pc.dim('-------------------------'));
    const contractName = isAddressEqual(log.address, options.protocol)
      ? pc.green('USDN Protocol')
      : isAddressEqual(log.address, options.usdn)
        ? pc.blue('USDN token')
        : pc.red('Oracle Middleware');
    console.log('Contract:', contractName, pc.dim(`(${log.address})`));
    const block = await client.getBlock({ blockNumber: log.blockNumber });
    console.log('Timestamp:', block.timestamp.toString());
    console.log(
      'DateTime:',
      pc.magenta(
        DateTime.fromSeconds(Number(block.timestamp)).setLocale('en-GB').toLocaleString(DateTime.DATETIME_FULL),
      ),
    );
    console.log('Block number:', log.blockNumber.toString());
    console.log('Event name:', pc.yellow(pc.bold(log.eventName)));
    console.log('Args:');
    for (const arg of Object.entries(log.args)) {
      const formattedValue = typeof arg[1] === 'bigint' && arg[1] !== 0n ? pc.dim(` (${formatEther(arg[1])})`) : '';
      console.log(pc.cyan(`  ${arg[0]}:`), `${arg[1]}${formattedValue}`);
    }
    console.log(pc.dim('-------------------------'));
  }
}

main();
