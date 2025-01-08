import fs, { readFileSync, writeFileSync } from 'node:fs';

/* ---------------------------------------------------------------------------------------- */
/*   This script's purpose it to fix the output of the `forge doc` command.                 */
/*   It will go through the generated HTML files and attempt to replace the broken links.   */
/* ---------------------------------------------------------------------------------------- */

const DOCS_BOOK_PATH = './docs/book/src';
const signaturesPerContract: Map<
  string,
  {
    path: string;
    signatures: { [elementSignature: string]: { name: string; href: string } };
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

function extractElementName(line: string) {
  const elementName = line.match(/<a[^>]*>([^<]+)<\/a>/)?.[1];
  const elementHref = line.match(/href="([^"]+)"/)?.[1];

  if (!elementName || !elementHref) {
    throw `extractElementName: Unexpected format for line: ${line}`;
  }

  return [elementName, elementHref];
}

function extractElementParameters(fileContent: string[], startIndex: number) {
  const parameterTypes: string[] = [];
  for (let i = startIndex; i < fileContent.length; i++) {
    const line = fileContent[i];
    // we are entering the doc of another element or the return types, so we should stop the iteration now and return what we got so far
    if (line.includes('<h3') || line === '<p><strong>Returns</strong></p>') {
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

function buildElementSignature(name: string, parameterTypes: string[]) {
  return `${name}(${parameterTypes.join(',')})`;
}

/** Save the function/event/struct signatures of a contract in the `signaturesPerContract` map */
function indexContractElements(docFiles: string[]) {
  for (let i = 0; i < docFiles.length; i++) {
    const docFile = docFiles[i];

    const lines = readFileSync(`${DOCS_BOOK_PATH}/${docFile}`, { encoding: 'utf-8' }).split('\n');
    const contractName = docFile.split('/').slice(-2, -1)[0].split('.')[0];

    if (!signaturesPerContract.has(contractName)) {
      signaturesPerContract.set(contractName, {
        path: `/src/${docFile}`,
        signatures: {},
      });
    }

    // find where the body of the documentation begins
    const startIndex = lines.findIndex((lineContent) => lineContent.includes('<main>'));

    for (let i = startIndex; i < lines.length; i++) {
      const line = lines[i];
      // h3 and h1 tags are used only as headers for documenting a function/event/struct/etc.
      if (line.includes('<h3') || line.includes('<h1')) {
        const [elementName, elementHref] = extractElementName(line);
        const parameterTypes = extractElementParameters(lines, i + 1);

        // the signature of an element that is found first is always the default choice if parameters are not specified
        // this helps the script deal with parameters overloading
        if (signaturesPerContract.get(contractName)?.signatures[elementName] === undefined) {
          // biome-ignore lint/style/noNonNullAssertion: cannot be null because of initialization earlier
          const contractData = signaturesPerContract.get(contractName)!;
          contractData.signatures[elementName] = {
            href: `${contractData.path}${elementHref}`,
            name: elementName,
          };
          signaturesPerContract.set(contractName, contractData);
        }

        // save the element signature and its reference
        // biome-ignore lint/style/noNonNullAssertion: cannot be null because of initialization earlier
        const contractData = signaturesPerContract.get(contractName)!;
        contractData.signatures[buildElementSignature(elementName, parameterTypes)] = {
          href: `${contractData.path}${elementHref}`,
          name: elementName,
        };
        signaturesPerContract.set(contractName, contractData);
      }
    }
  }
}

/** Fix the broken links in the documentation */
function fixDocFile(docFilePath: string) {
  let content = readFileSync(`${DOCS_BOOK_PATH}/${docFilePath}`, { encoding: 'utf-8' });
  const contractName = docFilePath.split('/').slice(-2, -1)[0].split('.')[0];
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

        // ignore empty functions that match the regexp
        if (stringToReplace === '{}') continue;

        const elementSelector = match[1];
        let [targetContractName, ...signatureElements] = elementSelector.split('.');
        let elementSignature = signatureElements.join('.');

        // if there is no element name, the broken link has a format of {xxxxx}
        // meaning that it's either a link to a contract/interface, or a link to an element in the same file
        if (!elementSignature) {
          // if the contract name exists in the mapping, then it's a link to a contract
          if (signaturesPerContract.has(targetContractName)) {
            // biome-ignore lint/style/noNonNullAssertion: cannot be null because of assertion above
            const contractData = signaturesPerContract.get(targetContractName)!;
            isRewriteNecessary = true;
            content = content.replaceAll(stringToReplace, `<a href="${contractData.path}">${targetContractName}</a>`);
            continue;
          }

          // if it doesn't, then it's most probably a link to an  element in the same file
          elementSignature = targetContractName;
          targetContractName = contractName;
        }

        // find the target contract and element signature to replace the broken link
        const targetSignature = signaturesPerContract.get(targetContractName)?.signatures[elementSignature];
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
