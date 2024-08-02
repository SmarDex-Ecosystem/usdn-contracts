import { readFileSync } from 'node:fs';
import { basename } from 'node:path';
import type { AbiFunction } from 'abitype';
import { Command } from 'commander';
import { globSync } from 'glob';
import { toFunctionSelector, toFunctionSignature } from 'viem';
import pc from 'picocolors';

const program = new Command();

program
  .description('Export ABI from artifacts')
  .argument('<contract1>', 'first contract to compare')
  .argument('<contract2>', 'second contract to compare')
  .option('-d, --debug', 'output extra debugging')
  .option('-sn, --same-name', 'output errors for functions with the same name')
  .parse(process.argv);

const options = program.opts();
const DEBUG: boolean = !!options.debug;
const SAME_NAME: boolean = !!options.sameName;
const contracts = program.args;

const solFiles = globSync(`src/UsdnProtocol/{${contracts.join(',')}}`);
if (solFiles.length !== 2) {
  console.log('\nPlease provide two valid contracts to compare');
  process.exit(1);
}

if (DEBUG) console.log('files:', solFiles);
for (const [i, file] of solFiles.entries()) {
  solFiles[i] = basename(file, '.sol');
}

const selectorMap = new Map<`0x${string}`, string>();
for (const name of solFiles) {
  try {
    const file = readFileSync(`./out/${name}.sol/${name}.json`);
    const artifact = JSON.parse(file.toString());

    artifact.abi
      .filter((abiItem: AbiFunction) => abiItem.type === 'function')
      .map((abiItem: AbiFunction) => {
        const selector = toFunctionSelector(abiItem);
        const signature = toFunctionSignature(abiItem);

        if (selectorMap.has(selector)) {
          const duplicateSignature = selectorMap.get(selector);

          if (duplicateSignature !== signature || SAME_NAME) {
            console.log(
              '\n',
              pc.bgRed('ERROR:'),
              `function ${pc.blue(signature)} in ${pc.green(name)} have the same selector (${selector})\n` +
                `\t    than ${pc.blue(duplicateSignature)} in ${pc.green(solFiles[0])}`,
            );
          }
        } else {
          selectorMap.set(selector, signature);
        }
      });
  } catch {
    console.log(`./out/${name}.sol/${name}.json does not exist`);
  }
}
