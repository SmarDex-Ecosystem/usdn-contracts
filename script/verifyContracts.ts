import {Command} from "commander";
import {existsSync, readFileSync} from "node:fs";
import {exec} from "child_process";
import {encodeAbiParameters} from 'viem'

const program = new Command();

program.description('Verify contract from broadcast file')
    .argument('<path>', 'path to the broadcast file')
    .requiredOption('-e, --etherscan-api-key <key>', "The Etherscan (or equivalent) API key")
    .option('--verifier-url <url>', "The verifier URL, if using a custom provider")
    .option('-d, --debug', 'output extra debugging')
    .parse(process.argv);

const broadcastPath = program.args[0];
const options = program.opts();
const DEBUG = !!options.debug;
let etherscanApiKey: string = options.etherscanApiKey;
let verifierUrl: string = options.verifierUrl;
const verbose: string = DEBUG ? '--verbose' : '';

if (DEBUG) console.log(`etherscanApiKey : ${etherscanApiKey}`)
if (DEBUG) console.log(`verifierUrl : ${verifierUrl}`)
if (DEBUG) console.log(`broadcastPath : ${broadcastPath}`)

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
    const argumentList: [any] = transaction.arguments;
    if (DEBUG) console.log(`transaction to verify with address : ${address} and name : ${contractName}`)
    if (DEBUG) console.log(`arguments of the contract : ${argumentList}`)

    const pathAbi: string = `./out/${contractName}.sol/${contractName}.json`;
    if (!existsSync(pathAbi)) {
        console.error(`Unable to reach ${pathAbi}, compile contracts of the project`)
    } else {
        const contractAbiFile = readFileSync(pathAbi);
        const contractAbi = JSON.parse(contractAbiFile.toString());
        let constructorInputs = undefined;
        try {
            constructorInputs = contractAbi.abi.filter((x: {
                type: string;
            }) => x.type == "constructor")[0].inputs
            if (DEBUG) {
                console.log(`constructorInputs : `)
                constructorInputs.forEach(x => console.log(x))
                if (constructorInputs.length == argumentList.length) {
                    console.log(`constructorInputsType and argumentList have the same amount of elements`)
                } else {
                    console.error(`constructorInputsType length: ${constructorInputs.length} != argumentList length: ${argumentList.length}`)
                }
            }
        } catch {
            console.error(`Unable to get constructor inputs type for ${contractName}`)
        }
        if (constructorInputs != undefined) {
            //build constructor args
            const encodedConstructorParameters = encodeAbiParameters(constructorInputs, argumentList)
            if (DEBUG) console.log(`encodedConstructorParameters : ${encodedConstructorParameters}`)

            const cli = `forge verify-contract ${address} ${contractName} --constructor-args ${encodedConstructorParameters} --watch  ${etherscanApiKey} ${verifierUrl} ${verbose}`;
            if (DEBUG) console.log(`cli : ${cli}`)

            exec(cli, (error, stdout, stderr) => {
                console.log(stdout);
                console.error(stderr);
            })
        }
    }
})
