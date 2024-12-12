import { execSync } from 'node:child_process';
import { existsSync, readFileSync } from 'node:fs';
import { Command } from 'commander';
import { encodeAbiParameters } from 'viem';

const program = new Command();

function execVerify(address: string, contractName: string, constructorArgs: string, libraries: string[]) {
  let cli = `forge verify-contract ${address} ${contractName} ${constructorArgs} --watch ${etherscanApiKey} ${verifierUrl} ${verbose}`;
  if (libraries.length > 0) {
    for (const lib of libraries) {
      cli = cli.concat(' --libraries ', lib);
    }
  }
  if (DEBUG) console.log(`cli : ${cli}`);

  try {
    const result = execSync(cli);
    console.log(result.toString());
  } catch (error) {
    console.log(error.stdout.toString());
    console.error(error.stderr.toString());
  }
}

program
  .description('Verify contract from broadcast file')
  .argument('<path>', 'path to the broadcast file')
  .requiredOption('-e, --etherscan-api-key <key>', 'The Etherscan (or equivalent) API key')
  .option('--verifier-url <url>', 'The verifier URL, if using a custom provider')
  .option('-d, --debug', 'output extra debugging')
  .parse(process.argv);

const broadcastPath = program.args[0];
const options = program.opts();
const DEBUG = !!options.debug;
let etherscanApiKey: string = options.etherscanApiKey;
let verifierUrl: string = options.verifierUrl;
const verbose: string = DEBUG ? '-vvvvv' : '';

if (DEBUG) console.log(`etherscanApiKey : ${etherscanApiKey}`);
if (DEBUG) console.log(`verifierUrl : ${verifierUrl}`);
if (DEBUG) console.log(`broadcastPath : ${broadcastPath}`);

if (!existsSync(broadcastPath)) {
  console.log('\nPlease provide a valid broadcast file');
  process.exit(1);
}

if (etherscanApiKey) etherscanApiKey = `-e ${etherscanApiKey}`;
verifierUrl = verifierUrl ? `--verifier-url ${verifierUrl}` : '';

const file = readFileSync(broadcastPath);
const broadcast = JSON.parse(file.toString());

const libraries: string[] = broadcast.libraries;
if (DEBUG) console.log(`libraries from broadcast file : ${libraries}`);

for (const transaction of broadcast.transactions.filter(
  (transaction) => transaction.transactionType === 'CREATE' || transaction.transactionType === 'CREATE2',
)) {
  const address: string = transaction.contractAddress;
  const contractName: string = transaction.contractName;
  const argumentList = transaction.arguments;
  if (DEBUG) console.log(`transaction to verify with address : ${address} and name : ${contractName}`);
  if (DEBUG) console.log(`arguments of the contract : ${argumentList}`);

  const pathOutFile: string = `./out/${contractName}.sol/${contractName}.json`;
  if (!existsSync(pathOutFile)) {
    console.error(`Unable to reach ${pathOutFile}, compile contracts of the project`);
  } else {
    const compiledContractOutFile = readFileSync(pathOutFile);
    const compiledContractOut = JSON.parse(compiledContractOutFile.toString());

    //get linked libraries
    const listLinkedLibraries: string[] = Object.keys(compiledContractOut.bytecode.linkReferences);
    if (DEBUG) console.log(`listLinkedLibraries : ${listLinkedLibraries}`);
    const librariesCli: string[] = [];
    if (listLinkedLibraries.length > 0) {
      for (const linkedLib of listLinkedLibraries) {
        const correspondingLib = libraries.find((x) => x.startsWith(linkedLib));
        if (correspondingLib === undefined) {
          if (DEBUG)
            console.error(
              `Unable to find linked lib ${linkedLib} of deployed contract ${contractName} in broadcast file`,
            );
        } else {
          librariesCli.push(correspondingLib);
        }
      }
      if (DEBUG) console.log(`librariesCli : ${librariesCli}`);
    }

    //get constructor arguments
    if (argumentList === null) {
      execVerify(address, contractName, '', librariesCli);
    } else {
      let constructorInputs: string[] = [];
      try {
        constructorInputs = compiledContractOut.abi.filter(
          (x: {
            type: string;
          }) => x.type === 'constructor',
        )[0].inputs;
        if (DEBUG) {
          console.log('constructorInputs : ');
          for (const x of constructorInputs) {
            console.log(x);
          }
          if (constructorInputs.length === argumentList.length) {
            console.log('constructorInputsType and argumentList have the same amount of elements');
          } else {
            console.error(
              `constructorInputsType length: ${constructorInputs.length} != argumentList length: ${argumentList.length}`,
            );
          }
        }
      } catch {
        console.error(`Unable to get constructor inputs type for ${contractName}`);
      }

      if (constructorInputs !== undefined) {
        //build constructor args
        const encodedConstructorParameters = encodeAbiParameters(constructorInputs, argumentList);
        if (DEBUG) console.log(`encodedConstructorParameters : ${encodedConstructorParameters}`);
        const constructorArgs = `--constructor-args ${encodedConstructorParameters}`;

        execVerify(address, contractName, constructorArgs, librariesCli);
      }
    }
  }
}
