import { execSync } from 'child_process';
import { readFileSync } from 'fs';
import { Command } from 'commander';
import 'dotenv/config';

const program = new Command();

program
  .description('Deploy the protocol with externally linked libraries')
  .requiredOption('-f, --from <ADDRESS>', 'The address to deploy from')
  .option('-r, --rpc-url <URL>', 'The RPC endpoint (env: ETH_RPC_URL)')
  .option('--private-key <RAW_PRIVATE_KEY>', 'The private key of the deployer')
  .option('-l, --ledger', 'Use a Ledger wallet')
  .option('-t, --trezor', 'Use a Trezor wallet')
  .option('-v, --verify', 'Verify the contracts on Etherscan')
  .option('-s, --setup', 'Additional setup when working on a fork')
  .parse();

const options = program.opts();

const cliArgs: string[] = [];
if (options.rpcUrl) {
  cliArgs.push('--rpc-url');
  cliArgs.push(options.rpcUrl);
}
if (options.privateKey) {
  cliArgs.push('--private-key');
  cliArgs.push(options.privateKey);
}
if (options.ledger) {
  cliArgs.push('-l');
}
if (options.trezor) {
  cliArgs.push('-t');
}
if (options.verify) {
  cliArgs.push('--verify');
}

const queueLib = JSON.parse(
  execSync(
    `forge create --json ${['-f', options.from, ...cliArgs].join(
      ' ',
    )} "src/libraries/DoubleEndedQueue.sol:DoubleEndedQueue"`,
  ).toString(),
).deployedTo;
console.log(`DoubleEndedQueue: ${queueLib}`);

const mathLib = JSON.parse(
  execSync(
    `forge create --json ${['-f', options.from, ...cliArgs].join(' ')} "src/libraries/SignedMath.sol:SignedMath"`,
  ).toString(),
).deployedTo;
console.log(`SignedMath: ${mathLib}`);

const tickLib = JSON.parse(
  execSync(
    `forge create --json ${['-f', options.from, ...cliArgs].join(' ')} "src/libraries/TickMath.sol:TickMath"`,
  ).toString(),
).deployedTo;
console.log(`TickMath: ${tickLib}`);

if (options.setup) {
  execSync(`forge script ${cliArgs.join(' ')} script/Fork.s.sol --broadcast`);
}

const deployArgs = [
  ...cliArgs,
  '--non-interactive',
  '--libraries',
  `"src/libraries/DoubleEndedQueue.sol:DoubleEndedQueue:${queueLib}"`,
  '--libraries',
  `"src/libraries/SignedMath.sol:SignedMath:${mathLib}"`,
  '--libraries',
  `"src/libraries/TickMath.sol:TickMath:${tickLib}"`,
];

const resString = execSync(`forge script ${deployArgs.join(' ')} script/Deploy.s.sol --broadcast`).toString();

const regex = /Transactions saved to: (\S+)/;
const match = resString.match(regex);

if (!match?.[1]) {
  console.error('JSON filepath not found in the text.');
  process.exit(1);
}

const jsonFilePath = match[1];
const file = readFileSync(jsonFilePath);
const data = JSON.parse(file.toString());
const middlewareAddress = data.transactions[0].contractAddress;
console.log(`OracleMiddleware: ${middlewareAddress}`);
const usdnAddress = data.transactions[1].contractAddress;
console.log(`USDN: ${usdnAddress}`);
const protocolAddress = data.transactions[2].contractAddress;
console.log(`Protocol: ${protocolAddress}`);
