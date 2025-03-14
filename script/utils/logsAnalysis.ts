// The ABIs are required a must be generated with `npm run exportAbi` prior to launching this script
import { Command } from 'commander';
import { DateTime } from 'luxon';
import pc from 'picocolors';
import {
  http,
  createPublicClient,
  createTestClient,
  formatEther,
  isAddressEqual,
  publicActions,
  webSocket,
} from 'viem';
import { IRebalancerAbi, IUsdnAbi, IUsdnProtocolEventsAbi } from '../../dist/abi';

function parseArgs() {
  const program = new Command();

  program
    .description('Retrieve and display all logs from the USDN protocol')
    .option(
      '-p, --protocol <address>',
      'address of the USDN protocol contract',
      '0x656cb8c6d154aad29d8771384089be5b5141f01a',
    )
    .option('-u, --usdn <address>', 'address of the USDN token contract', '0xde17a000ba631c5d7c2bd9fb692efea52d90dee2')
    .option(
      '--rebalancer <address>',
      'address of the rebalancer contract',
      '0xaeBcc85a5594e687F6B302405E6E92D616826e03',
    )
    .option('-r, --rpc-url <url>', 'URL of the RPC node to connect to')
    .option('-b, --blocks <blocks>', 'number of blocks to retrieve', '1000')
    .parse(process.argv);

  return program.opts();
}

function getClient(rpcUrl: string) {
  const url = new URL(rpcUrl);
  if (url.hostname === 'localhost') {
    return createTestClient({
      mode: 'anvil',
      transport: url.protocol === 'http:' ? http(rpcUrl) : webSocket(rpcUrl),
    }).extend(publicActions);
  }
  if (url.protocol === 'ws:' || url.protocol === 'wss:') {
    return createPublicClient({
      transport: webSocket(rpcUrl),
    });
  }
  return createPublicClient({
    transport: http(rpcUrl),
  });
}

async function main() {
  const options = parseArgs();

  if (!options.rpcUrl) {
    console.error('Please specify the RPC URL');
    process.exit(1);
  }

  const client = getClient(options.rpcUrl);

  const protocolEvents = IUsdnProtocolEventsAbi.filter((item) => item.type === 'event');
  const usdnEvents = IUsdnAbi.filter((item) => item.type === 'event');
  const rebalancerEvents = IRebalancerAbi.filter((item) => item.type === 'event');

  const startBlock = (await client.getBlockNumber()) - BigInt(options.blocks);

  const protocolLogs = await client.getLogs({
    address: options.protocol,
    events: protocolEvents,
    fromBlock: startBlock,
  });
  const usdnLogs = await client.getLogs({
    address: options.usdn,
    events: usdnEvents,
    fromBlock: startBlock,
  });
  const rebalancerLogs = await client.getLogs({
    address: options.rebalancer,
    events: rebalancerEvents,
    fromBlock: startBlock,
  });

  const logs = [...protocolLogs, ...usdnLogs, ...rebalancerLogs];
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
        : pc.red('Rebalancer');
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
    console.log('TX Hash:', log.transactionHash);
    console.log('Event name:', pc.yellow(pc.bold(log.eventName)));
    console.log('Args:');
    for (const arg of Object.entries(log.args)) {
      // if value is an object, we stringify it
      const value =
        typeof arg[1] === 'object'
          ? JSON.stringify(arg[1], (_, value) => (typeof value === 'bigint' ? value.toString() : value))
          : arg[1];
      // if value is a bigint, we add the value in ether
      const formattedValue = typeof arg[1] === 'bigint' && arg[1] !== 0n ? pc.dim(` (${formatEther(arg[1])})`) : '';
      console.log(pc.cyan(`  ${arg[0]}:`), `${value}${formattedValue}`);
    }
    console.log(pc.dim('-------------------------'));
  }
}

main();
