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
  .option('-d, --debug', 'output extra debugging')
  .option('-c, --common-dep <paths...>', 'common dependencies paths')
  .parse(process.argv);

const options = program.opts();
const DEBUG = !!options.debug;
const commonDeps = options.commonDep || false;
const contracts = program.args;

const commonMap = handleCommonDependencies(commonDeps);

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

// check for clashes
let globSelectorMap = new Map<`0x${string}`, string>();
for (const file of solFiles) {
  const fileMap = createFunctionMap(file);
  globSelectorMap.forEach((selector, signature) => {
    if (fileMap.has(signature) && !commonMap.has(signature)) {
      console.log(pc.red('\nFunction clash detected with :'), pc.yellow(selector), pc.green(signature));
      process.exit(1);
    }
  });

  globSelectorMap = new Map([...globSelectorMap, ...fileMap]);
}

function handleCommonDependencies(commonDeps: string[]): Map<`0x${string}`, string> {
  let commonSelectorMap = new Map<`0x${string}`, string>();

  for (const commonDep of commonDeps) {
    const depMap = createFunctionMap(commonDep);
    commonSelectorMap = new Map([...commonSelectorMap, ...depMap]);
  }
  return commonSelectorMap;
}

function createFunctionMap(contractName: string): Map<`0x${string}`, string> {
  const selectorMap = new Map<`0x${string}`, string>();
  const path = `./out/${contractName}.sol/${contractName}.json`;

  try {
    const fileContent = readFileSync(path);
    const artifact = JSON.parse(fileContent.toString());

    const abiItems = artifact.abi.filter((abiItem: AbiFunction) => abiItem.type === 'function');
    for (const abiItem of abiItems) {
      const selector = toFunctionSelector(abiItem);
      const signature = toFunctionSignature(abiItem);

      if (selectorMap.has(selector)) {
        const existingSignature = selectorMap.get(selector);
        if (DEBUG) {
          console.log(`${signature}: selector ${selector} is already in the map with signature ${existingSignature}`);
        }
      } else {
        selectorMap.set(selector, signature);
      }
    }
  } catch {
    console.log(`Error with ${path}`);
  }

  return selectorMap;
}
