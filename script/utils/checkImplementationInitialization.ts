import { readFileSync, existsSync } from 'node:fs';
import { Command } from 'commander';

const program = new Command();

program
  .description('Check if the implementation initializer is disabled')
  .argument('implementation', 'the implementation contract')
  .allowExcessArguments(false)
  .option('-d, --debug', 'output extra debugging')
  .parse(process.argv);

const options = program.opts();
const DEBUG = !!options.debug;
const implementation = program.args;
const path = `src/UsdnProtocol/${implementation}.sol`;

if (DEBUG) console.log('implementation path:', path);

// parse arguments
if (!existsSync(path)) {
  console.log('\nPlease provide a valid contract');
  process.exit(1);
}

// check constructor with _disableInitializers function
const constructorDisabledInitializers = `
    /// @custom:oz-upgrades-unsafe-allow constructor
    constructor() {
        _disableInitializers();
    }`;

const fileContent = readFileSync(path);
if (!fileContent.includes(constructorDisabledInitializers)) {
  console.log('\nImplementation initializer is enabled, please disable it');
  process.exit(1);
}
