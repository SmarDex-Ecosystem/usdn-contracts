import {Command} from "commander";
import {existsSync, readFileSync} from "node:fs";
import {exec} from "child_process";

const program = new Command();

program.description('Verify contract from broadcast file')
    .argument('<path>', 'path to the broadcast file')
    // .requiredOption('-r', '--rpc-url <url>', "The RPC endpoint")
    .requiredOption('-e', '--etherscan-api-key <key>', "The Etherscan (or equivalent) API key")
    .option('--verifier-url <url>', "The verifier URL, if using a custom provider")
    .option('-d, --debug', 'output extra debugging')
    .parse(process.argv);

const broadcastPath = program.args[0];
const options = program.opts();
const DEBUG = !!options.debug;
let etherscanApiKey: string = options.etherscanApiKey;
let verifierUrl: string = options.verifierUrl;
const verbose: string = DEBUG ? '--verbose' : '';

if (!existsSync(broadcastPath)) {
    console.log('\nPlease provide a valid broadcast file');
    process.exit(1);
}

if (etherscanApiKey) etherscanApiKey = `-e ${etherscanApiKey}`;
if (verifierUrl) verifierUrl = `--verifier-url ${verifierUrl}`;

const file = readFileSync(broadcastPath);
const broadcast = JSON.parse(file.toString());
broadcast.transactions.filter(transaction =>
    transaction.transactionType == "CREATE"
).forEach(transaction => {
    const address: string = transaction.contractAddress;
    const contractName: string = transaction.contractName;
    const cli = `forge verify-contract ${address} ${contractName} --guess-constructor-args --watch ${etherscanApiKey} ${verifierUrl} ${verbose}`;
    exec(cli, (error, stdout, stderr) => {
        console.log(stdout);
        console.error(stderr);
    })
})