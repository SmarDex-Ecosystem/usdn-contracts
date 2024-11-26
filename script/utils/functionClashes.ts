import { readFileSync } from 'node:fs';
import type { AbiFunction } from 'abitype';
import { Command } from 'commander';
import { toFunctionSelector, toFunctionSignature } from 'viem';
import pc from 'picocolors';
import { execSync } from 'node:child_process';

const program = new Command();

program
  .description('Check if two contracts have functions with the same selector')
  .argument('<contract1>', 'first contract to compare')
  .argument('<contract2>', 'second contract to compare')
  .allowExcessArguments(false)
  .option('-d, --debug', 'output extra debugging')
  .option('-c, --common-dep <contractNames...>', 'common contract dependencies names')
  .parse(process.argv);

// argument and options
const options = program.opts();
const DEBUG = !!options.debug;
const commonDeps = options.commonDep;
const contracts = program.args;

if (DEBUG) {
  console.log('options:', options);
  console.log('contracts:', contracts);
}
const commonMap = handleCommonDependencies(commonDeps);

// build contracts
if (DEBUG) console.log('Building contracts...');
execSync('forge build src');

// check for clashes
let globSelectorMap = new Map<`0x${string}`, string>();
for (const contract of contracts) {
  const fileMap = createSelectorMap(contract);
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
  if (!commonDeps) return commonSelectorMap;

  for (const commonDepName of commonDeps) {
    const depSelectorMap = createSelectorMap(commonDepName);
    commonSelectorMap = new Map([...commonSelectorMap, ...depSelectorMap]);
  }

  return commonSelectorMap;
}

function createSelectorMap(contractName: string): Map<`0x${string}`, string> {
  const selectorMap = new Map<`0x${string}`, string>();
  const path = `./out/${contractName}.sol/${contractName}.json`;

  try {
    const fileContent = readFileSync(path);
    const artifact = JSON.parse(fileContent.toString());

    const abiItems = artifact.abi.filter((abiItem: AbiFunction) => abiItem.type === 'function');
    for (const abiItem of abiItems) {
      selectorMap.set(toFunctionSelector(abiItem), toFunctionSignature(abiItem));
    }
  } catch {
    console.log(`Error with ${path}`);
    process.exit(1);
  }

  return selectorMap;
}
