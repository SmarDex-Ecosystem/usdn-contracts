import { existsSync, mkdirSync, readFileSync, rmSync, writeFileSync } from 'fs';
import { basename } from 'path';
import { AbiError, AbiEvent, AbiFunction, formatAbiItem } from 'abitype';
import { Command } from 'commander';
import { globSync } from 'glob';
import { toEventSelector, toEventSignature, toFunctionSelector, toFunctionSignature } from 'viem';

const ABI_EXPORT_PATH = './dist/abi';

type EnumMember = {
  name: string;
};

type EnumNode = {
  nodeType: string;
  canonicalName: string;
  members: EnumMember[];
};

const program = new Command();

program
  .description('Export ABI from artifacts')
  .option('-g, --glob <filter>', "Only includes files in 'src' that match the provided glob (defaults to '**/*.sol').")
  .option('-d, --debug', 'output extra debugging')
  .parse(process.argv);

const options = program.opts();
const glob = options.glob || '**/*.sol';
const DEBUG: boolean = options.debug ? true : false;

const solFiles = globSync(`src/${glob}`);
if (DEBUG) console.log('files:', solFiles);
for (const [i, file] of solFiles.entries()) {
  solFiles[i] = basename(file, '.sol');
}

if (existsSync(ABI_EXPORT_PATH)) rmSync(ABI_EXPORT_PATH, { recursive: true, force: true });
mkdirSync(ABI_EXPORT_PATH, { recursive: true });

let indexContent = '';

for (const name of solFiles) {
  try {
    const file = readFileSync(`./out/${name}.sol/${name}.json`);
    const artifact = JSON.parse(file.toString());

    const fileContent = `export const ${name}Abi = ${JSON.stringify(artifact.abi, null, 2)} as const;\n`;

    const selectors = artifact.abi
      .filter(
        (abiItem: AbiFunction | AbiEvent | AbiError) =>
          abiItem.type === 'function' || abiItem.type === 'event' || abiItem.type === 'error',
      )
      .map((abiItem: AbiFunction | AbiEvent | AbiError) => {
        if (abiItem.type === 'function') {
          const signature = toFunctionSignature(abiItem);
          const selector = toFunctionSelector(abiItem);
          return `// ${selector}: function ${signature}\n`;
        }
        if (abiItem.type === 'event') {
          const signature = toEventSignature(abiItem);
          const selector = toEventSelector(abiItem);
          return `// ${selector}: event ${signature}\n`;
        }
        if (abiItem.type === 'error') {
          const signature = formatAbiItem(abiItem);
          const selector = toFunctionSelector(signature.slice(6)); // remove 'error ' from signature
          return `// ${selector}: ${signature}\n`;
        }
      });
    selectors.sort();

    writeFileSync(`${ABI_EXPORT_PATH}/${name}.ts`, fileContent + selectors.join(''));
    indexContent += `export * from './${name}';\n`;
  } catch {
    // Could be normal, if a solidity file does not contain a contract (only an interface)
    console.log(`./out/${name}.sol/${name}.json does not exist`);
  }
}

// Get all enums
const outFiles = globSync('out/**/*.json', { withFileTypes: true });
if (DEBUG) console.log('artifacts:', outFiles);

const allEnums: Map<string, string> = new Map();
for (const artifact of outFiles) {
  try {
    const file = readFileSync(artifact.fullpath());
    const {
      ast: { nodes },
    } = JSON.parse(file.toString());
    const enums = nodes.filter((node: EnumNode) => node.nodeType === 'EnumDefinition');
    for (const enum_ of enums) {
      const members = enum_.members.map((member: EnumMember) => `  ${member.name}`);
      allEnums.set(enum_.canonicalName, `export enum ${enum_.canonicalName} {\n${members.join(',\n')}\n};\n`);
    }
  } catch {
    console.log(`${artifact.fullpath()} does not exist`);
  }
}
if (DEBUG) console.log(allEnums);
const fileContent = [...allEnums.values()].join('\n');
writeFileSync(`${ABI_EXPORT_PATH}/Enums.ts`, fileContent);
indexContent += `export * from './Enums';\n`;

writeFileSync(`${ABI_EXPORT_PATH}/index.ts`, indexContent);
