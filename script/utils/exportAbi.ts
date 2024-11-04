import { existsSync, mkdirSync, readFileSync, rmSync, writeFileSync } from 'node:fs';
import { basename } from 'node:path';
import { type AbiError, type AbiEvent, type AbiFunction, formatAbiItem } from 'abitype';
import { Command } from 'commander';
import { globSync } from 'glob';
import { toEventSelector, toEventSignature, toFunctionSelector, toFunctionSignature } from 'viem';

const ABI_EXPORT_PATH = './dist/abi';

type EnumMember = {
  name: string;
};

type Node = {
  nodeType: string;
};

type NonterminalNode = Node & {
  nodes: (NonterminalNode | EnumNode)[];
};

type EnumNode = Node & {
  canonicalName: string;
  members: EnumMember[];
};

function isNonterminal(node: Node): node is NonterminalNode {
  return node.nodeType === 'ContractDefinition'; // can add more types later if necessary
}

function isEnum(node: Node): node is EnumNode {
  return node.nodeType === 'EnumDefinition';
}

function getEnums(parentNode: NonterminalNode) {
  const enums: Map<string, string> = new Map();
  for (const node of parentNode.nodes) {
    if (isNonterminal(node)) {
      const childrenEnums = getEnums(node);
      for (const item of childrenEnums) {
        enums.set(item[0], item[1]);
      }
    } else if (isEnum(node)) {
      const members = node.members.map((member: EnumMember) => `  ${member.name}`);
      enums.set(
        node.canonicalName,
        `export enum ${sanitizeEnumName(node.canonicalName)} {\n${members.join(',\n')}\n};\n`,
      );
    }
  }
  return enums;
}

function sanitizeEnumName(canonicalName: string) {
  return canonicalName.replace('.', '');
}

const program = new Command();

program
  .description('Export ABI from artifacts')
  .option('-g, --glob <filter>', "Only includes files in 'src' that match the provided glob (defaults to '**/*.sol').")
  .option('-d, --debug', 'output extra debugging')
  .parse(process.argv);

const options = program.opts();
const glob = options.glob || '**/*.sol';
const DEBUG: boolean = !!options.debug;

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

const allEnums: Map<string, string> = new Map();
for (const artifact of outFiles) {
  try {
    if (DEBUG) console.log('processing file', artifact.fullpath());
    const file = readFileSync(artifact.fullpath());
    const { ast } = JSON.parse(file.toString());
    const enums = getEnums(ast as NonterminalNode);
    for (const item of enums) {
      allEnums.set(item[0], item[1]);
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
