import fs, { readFileSync, writeFile, writeFileSync } from 'node:fs';

const DOCS_BOOK_PATH = './docs/book/src';

const signaturesPerContract: Map<
  string,
  {
    path: string;
    signatures: { [functionSignature: string]: { name: string; href: string } };
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
  const functionName = line.match(/<a[^>]*>([^<]+)<\/a>/)?.[1];
  const functionHref = line.match(/href="([^"]+)"/)?.[1];

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

    // match parameters inside code tags
    const matches = [...line.matchAll(/<code>([^<]+)<\/code>/g)];
    if (matches?.[1]?.[1]) {
      parameterTypes.push(matches[1][1]);
    }
  }

  return parameterTypes;
}

function buildFunctionSignature(name: string, parameterTypes: string[]) {
  return `${name}(${parameterTypes.join(',')})`;
}

/** Save the function/event/struct signatures of a contract in the `signaturesPerContract` map */
function indexContractElements(docFiles: string[]) {
  for (let i = 0; i < docFiles.length; i++) {
    const docFile = docFiles[i];

    const content = readFileSync(`${DOCS_BOOK_PATH}/${docFile}`, { encoding: 'utf-8' }).split('\n');
    const contractName = docFile.split('/').slice(-2, -1)[0].split('.')[0];

    signaturesPerContract.set(contractName, {
      path: `/src/${docFile}`,
      signatures: {},
    });

    for (let i = 0; i < content.length; i++) {
      const line = content[i];
      // h3 tags are used only as headers for documenting a function/event/struct/etc.
      if (line.includes('<h3')) {
        const [functionName, functionHref] = extractFunctionName(line);
        const parameterTypes = extractFunctionParameters(content, i + 1);

        // the signature of a function that is found first is always the default choice if parameters are not specified
        // this helps the script deal with parameters overloading
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
function fixDocFile(docFilePath: string) {
  let content = readFileSync(`${DOCS_BOOK_PATH}/${docFilePath}`, { encoding: 'utf-8' });
  const lines = content.split('\n');

  // find where the body of the documentation begins
  const startIndex = lines.findIndex((lineContent) => lineContent.includes('<main>'));

  let isRewriteNecessary = false;
  for (let i = startIndex; i < lines.length; i++) {
    const line = lines[i];
    // this signifies the end of the body of the documentation anything after that is irrelevant
    if (line.includes('</main>')) {
      break;
    }

    // find anything between brackets in the current line
    const matches = [...line.matchAll(/\{([^}]*)\}/g)];
    if (matches.length > 0) {
      for (let j = 0; j < matches.length; j++) {
        const match = matches[j];
        const stringToReplace = match[0];
        const functionSelector = match[1];
        const [targetContractName, functionName] = functionSelector.split('.');

        // find the target contract and function signature to replace the broken link
        // if it cannot be found, ignore it
        const targetSignature = signaturesPerContract.get(targetContractName)?.signatures[functionName];
        if (targetSignature) {
          isRewriteNecessary = true;
          content = content.replaceAll(
            stringToReplace,
            `<a href="${targetSignature.href}">${targetSignature.name}</a>`,
          );
        } else {
          console.warn(`Could not find signature for link ${stringToReplace} in ${docFilePath}`);
        }
      }
    }
  }

  // rewrite the file if necessary
  if (isRewriteNecessary) writeFileSync(`${DOCS_BOOK_PATH}/${docFilePath}`, content);
}

const docFiles = getRelevantDocFiles();
indexContractElements(docFiles);
for (let i = 0; i < docFiles.length; i++) {
  fixDocFile(docFiles[i]);
}
