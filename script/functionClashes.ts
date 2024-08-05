import { readFileSync } from 'node:fs';
import { basename } from 'node:path';
import type { AbiFunction } from 'abitype';
import { Command } from 'commander';
import { globSync } from 'glob';
import { toFunctionSelector, toFunctionSignature } from 'viem';
import pc from 'picocolors';

const program = new Command();

program
  .description('Check if two contracts have functions with the same selector')
  .argument('<contract1>', 'first contract to compare')
  .argument('<contract2>', 'second contract to compare')
  .allowExcessArguments(false)
  .option('-s, --storage <storageContract>', 'the common storage layout')
  .option('-d, --debug', 'output extra debugging')
  .parse(process.argv);

const options = program.opts();
const DEBUG: boolean = !!options.debug;
const STORAGE: string = options.storage;
const contracts = program.args;
let storageFunctions: string[] = []; // if storage contract is provided, we will ignore its functions because they are common

// parse arguments
const solFiles = globSync(`src/UsdnProtocol/{${contracts.join(',')}}`);
if (solFiles.length !== 2) {
  console.log('\nPlease provide two valid contracts to compare');
  process.exit(1);
}

if (DEBUG) console.log('contracts:', solFiles);
for (const [i, file] of solFiles.entries()) {
  solFiles[i] = basename(file, '.sol');
}

// parse storage contract
if (STORAGE) {
  const storage = `src/UsdnProtocol/${STORAGE}`;

  if (DEBUG) console.log('storage:', storage);
  const storageName = basename(storage, '.sol');

  try {
    const file = readFileSync(`./out/${storageName}.sol/${storageName}.json`);
    const artifact = JSON.parse(file.toString());
    storageFunctions = artifact.abi
      .filter((abiItem: AbiFunction) => abiItem.type === 'function')
      .map((abiItem: AbiFunction) => toFunctionSignature(abiItem));
  } catch {
    console.error(`\n./out/${storageName}.sol/${storageName}.json does not exist`);
    process.exit(1);
  }
}

// check for clashes
const selectorMap = new Map<`0x${string}`, string>();
for (const name of solFiles) {
  try {
    const file = readFileSync(`./out/${name}.sol/${name}.json`);
    const artifact = JSON.parse(file.toString());

    const abiItems = artifact.abi.filter((abiItem: AbiFunction) => abiItem.type === 'function');
    for (const abiItem of abiItems) {
      const selector = toFunctionSelector(abiItem);
      const signature = toFunctionSignature(abiItem);

      if (selectorMap.has(selector)) {
        if (STORAGE && storageFunctions.includes(signature)) continue;

        // if the function selector is already in the map
        // and it is not in the storage contract then we have a clash
        console.log(
          '\n',
          pc.bgRed('ERROR:'),
          `function ${pc.blue(signature)} in ${pc.green(name)} have the same selector (${selector})\n`,
          `\t    than ${pc.blue(selectorMap.get(selector))} in ${pc.green(solFiles[0])}`,
        );
      } else {
        selectorMap.set(selector, signature);
      }
    }
  } catch {
    console.log(`./out/${name}.sol/${name}.json does not exist`);
  }
}
