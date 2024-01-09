import { writeFileSync, existsSync, mkdirSync, readFileSync, rmSync } from "fs";
import { globSync } from "glob";
import { basename } from "path";
import { Command } from "commander";

const ABI_EXPORT_PATH = "./dist/abi";

const program = new Command();

program
  .description("Export ABI from artifacts")
  .option(
    "-g, --glob <filter>",
    "Only includes files in 'src' that match the provided glob (defaults to '**/*.sol')."
  )
  .option("-d, --debug", "output extra debugging")
  .parse(process.argv);

const options = program.opts();
const glob = options.glob || "**/*.sol";
const DEBUG: boolean = options.debug ? true : false;

let solFiles = globSync(`src/${glob}`);
if (DEBUG) console.log("files:", solFiles);
solFiles.forEach((file, i) => {
  solFiles[i] = basename(file, ".sol");
});

if (existsSync(ABI_EXPORT_PATH))
  rmSync(ABI_EXPORT_PATH, { recursive: true, force: true });
mkdirSync(ABI_EXPORT_PATH, { recursive: true });

let indexContent = "";

for (const name of solFiles) {
  try {
    const file = readFileSync(`./out/${name}.sol/${name}.json`);
    const artifact = JSON.parse(file.toString());
    const { bytecode: { object: bytes } } = artifact;

    const fileContent = `export const ${name}Abi = ${JSON.stringify(
      artifact.abi,
      null,
      2
    )} as const;\n`;

    writeFileSync(`${ABI_EXPORT_PATH}/${name}.ts`, fileContent);
    indexContent += `export * from './${name}';\n`;
  } catch {
    // Could be normal, if a solidity file does not contain a contract (only an interface)
    console.log(`./out/${name}.sol/${name}.json does not exist`);
  }
}

writeFileSync(`${ABI_EXPORT_PATH}/index.ts`, indexContent);
