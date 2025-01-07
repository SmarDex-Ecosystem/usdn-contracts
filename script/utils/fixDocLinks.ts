import fs, { readFileSync } from 'node:fs';

const DOCS_BOOK_PATH = './docs/book/src/';
const TAG_H3_HREF_REGEX = /href="([^"]+)"/;
const TAG_H3_NAME_REGEX = /<a[^>]*>([^<]+)<\/a>/;
const PARAMETERS_TYPE_REGEX = /<code>([^<]+)<\/code>/g;

const signaturesPerContract: Map<
  string,
  {
    path: string;
    signatures: { name: string; href: string }[];
  }
> = new Map();

/** Returns an array of paths to files containing NatSpecs documentation. */
function getRelevantDocFiles() {
  return fs
    .readdirSync(DOCS_BOOK_PATH, {
      recursive: true,
    })
    .filter((path) => {
      if (typeof path !== 'string') {
        return false;
      }

      // index.html files do not contain NatSpecs documentation so we can ignore them
      const fileName = path.split('/').pop();
      if (fileName === 'index.html') return false;

      // a file without a .html extension is a directory and must be ignored
      const fileExtension = path.split('.').pop();
      return fileExtension === 'html';
    }) as string[];
}

function extractFunctionName(line: string) {
  const functionName = line.match(TAG_H3_NAME_REGEX)?.[1];
  const functionHref = line.match(TAG_H3_HREF_REGEX)?.[1];

  if (!functionName || !functionHref) {
    throw `extractFunctionName: Unexpected format for line: ${line}`;
  }

  return [functionName, functionHref];
}

function extractFunctionParameters(fileContent: string[], startIndex: number) {
  const parameterTypes: string[] = [];
  for (let i = startIndex; i < fileContent.length; i++) {
    const line = fileContent[i];
    // we are entering the doc of another element, so we should stop the iteration now and return what we got so far
    if (line.includes('<h3')) {
      return parameterTypes;
    }

    const matches = [...line.matchAll(PARAMETERS_TYPE_REGEX)];
    if (matches?.[1]?.[1]) {
      parameterTypes.push(matches[1][1]);
    }
  }

  return parameterTypes;
}

function buildFunctionSignature(name: string, parameterTypes: string[]) {
  return `${name}(${parameterTypes.join(',')})`;
}

/** Save the function/event/struct signatures in the `signaturesPerContract` map */
function indexContractElements(docFiles: string[]) {
  for (let i = 0; i < docFiles.length; i++) {
    const docFile = docFiles[i];

    const content = readFileSync(`${DOCS_BOOK_PATH}/${docFile}`, { encoding: 'utf-8' }).split('\n');
    const contractName = docFile.split('/').slice(-2, -1)[0].split('.')[0];

    signaturesPerContract.set(contractName, {
      path: `/src/${docFile}`,
      signatures: [],
    });

    for (let i = 0; i < content.length; i++) {
      const line = content[i];
      if (line.includes('<h3')) {
        const [functionName, functionHref] = extractFunctionName(line);
        const parameterTypes = extractFunctionParameters(content, i + 1);

        // the signature of a function that is found first is always the default choice if parameters are not specified
        if (signaturesPerContract.get(contractName)?.signatures[functionName] === undefined) {
          // biome-ignore lint/style/noNonNullAssertion: cannot be null because of initialization earlier
          const contractData = signaturesPerContract.get(contractName)!;
          contractData.signatures[functionName] = {
            href: `${contractData.path}${functionHref}`,
            name: functionName,
          };
          signaturesPerContract.set(contractName, contractData);
        }

        // save the function signature and its reference
        // biome-ignore lint/style/noNonNullAssertion: cannot be null because of initialization earlier
        const contractData = signaturesPerContract.get(contractName)!;
        contractData.signatures[buildFunctionSignature(functionName, parameterTypes)] = {
          href: `${contractData.path}${functionHref}`,
          name: functionName,
        };
        signaturesPerContract.set(contractName, contractData);
      }
    }
  }
}

/** Fix the broken links in the documentation */
function fixDoc(docFiles: string[]) {}

const docFiles = getRelevantDocFiles();
indexContractElements(docFiles);

console.log(signaturesPerContract);
