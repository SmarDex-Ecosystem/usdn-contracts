import fs, { readFileSync, writeFileSync } from 'node:fs';

/* -------------------------------------------------------------------------------------- */
/*   This script's purpose is to fix the output of the `forge doc` command.               */
/*   It will go through the generated MD files and attempt to replace the broken links.   */
/* -------------------------------------------------------------------------------------- */

const DOCS_MD_PATH = './docs/src/src';
const signaturesPerFile: Map<
  string,
  {
    path: string;
    signatures: { [elementSignature: string]: { name: string; href: string } };
  }
> = new Map();

/** Returns an array of paths to files containing NatSpecs documentation. */
function getRelevantDocFiles() {
  return fs
    .readdirSync(DOCS_MD_PATH, {
      recursive: true,
    })
    .filter((path) => {
      if (typeof path !== 'string') {
        return false;
      }

      // README.md files do not contain NatSpecs documentation so we can ignore them
      const fileName = path.split('/').pop();
      if (fileName === 'README.md') return false;

      // a file without a .md extension is a directory and must be ignored
      const fileExtension = path.split('.').pop();
      return fileExtension === 'md';
    }) as string[];
}

function extractElementName(line: string) {
  const elementName = line.split(' ').pop();
  if (!elementName) {
    throw `extractElementName: Unexpected format for line: ${line}`;
  }

  const elementHref = `#${elementName.toLowerCase()}`;

  return [elementName, elementHref];
}

function extractElementParameters(fileContent: string[], startIndex: number) {
  const parameterTypes: string[] = [];
  for (let i = startIndex; i < fileContent.length; i++) {
    const line = fileContent[i];
    // we are entering the doc of another element or the return types, so we should stop the iteration now and return what we got so far
    if (line.includes('###') || line === '**Returns**') {
      return parameterTypes;
    }

    // match parameters inside back quotes
    const matches = [...line.matchAll(/`([^`]+)`/g)];
    if (matches?.[1]?.[1]) {
      parameterTypes.push(matches[1][1]);
    }
  }

  return parameterTypes;
}

function buildElementSignature(name: string, parameterTypes: string[]) {
  return `${name}(${parameterTypes.join(',')})`;
}

/** Save the function/event/struct signatures of a contract in the `signaturesPerFile` map */
function indexContractElements(docFiles: string[]) {
  for (let i = 0; i < docFiles.length; i++) {
    const docFile = docFiles[i];

    const lines = readFileSync(`${DOCS_MD_PATH}/${docFile}`, { encoding: 'utf-8' }).split('\n');
    const contractName = docFile.split('/').slice(-2, -1)[0].split('.')[0];
    const docType = docFile.split('/').pop()?.split('.')[0] ?? '';

    if (!signaturesPerFile.has(contractName)) {
      signaturesPerFile.set(contractName, {
        path: `/src/${docFile}`,
        signatures: {},
      });
    }

    for (let i = 0; i < lines.length; i++) {
      const line = lines[i];
      // function/event/struct/etc in a file which is a contract or an interface always begin with '###'
      // if the struct/enum is not in a contract or an interface, a file will be generated per element
      // in that case, the name of the element is at the top of the file and begins with a '#'
      if (line.includes('###') || (!['contract', 'interface'].includes(docType) && line.includes('#'))) {
        const [elementName, elementHref] = extractElementName(line);
        const parameterTypes = extractElementParameters(lines, i + 1);

        // the signature of an element that is found first is always the default choice if parameters are not specified
        // this helps the script deal with parameters overloading
        let isDefault = false;
        if (signaturesPerFile.get(contractName)?.signatures[elementName] === undefined) {
          // biome-ignore lint/style/noNonNullAssertion: cannot be null because of initialization earlier
          const contractData = signaturesPerFile.get(contractName)!;
          contractData.signatures[elementName] = {
            href: `${contractData.path}${elementHref}`,
            name: elementName,
          };
          signaturesPerFile.set(contractName, contractData);
          isDefault = true;
        }

        // save the element signature and its reference
        // biome-ignore lint/style/noNonNullAssertion: cannot be null because of initialization earlier
        const contractData = signaturesPerFile.get(contractName)!;
        contractData.signatures[buildElementSignature(elementName, parameterTypes)] = {
          href: `${contractData.path}${elementHref}${isDefault ? '' : '-1'}`,
          name: elementName,
        };
        signaturesPerFile.set(contractName, contractData);
      }
    }
  }
}

/** Fix the broken links in the documentation */
function fixDocFile(docFilePath: string) {
  let content = readFileSync(`${DOCS_MD_PATH}/${docFilePath}`, { encoding: 'utf-8' });
  const contractName = docFilePath.split('/').slice(-2, -1)[0].split('.')[0];
  const lines = content.split('\n');

  let isRewriteNecessary = false;
  for (let i = 0; i < lines.length; i++) {
    const line = lines[i];
    // find anything between curly braces in the current line
    const matches = [...line.matchAll(/\{([^}]*)\}/g)];
    if (matches.length > 0) {
      for (let j = 0; j < matches.length; j++) {
        const match = matches[j];
        const stringToReplace = match[0];

        // ignore empty functions that match the regexp
        if (stringToReplace === '{}') continue;

        const elementSelector = match[1];
        let [targetContractName, ...signatureParts] = elementSelector.split('.');
        let elementSignature = signatureParts.join('.');

        // if there is no element signature, the broken link has a format of {xxxxx}
        // meaning that it's either a link to a contract/interface, or a link to an element in the same file
        if (!elementSignature) {
          // if the contract name exists in the mapping, then it's a link to a contract
          if (signaturesPerFile.has(targetContractName)) {
            // biome-ignore lint/style/noNonNullAssertion: cannot be null because of assertion above
            const contractData = signaturesPerFile.get(targetContractName)!;
            isRewriteNecessary = true;
            content = content.replaceAll(stringToReplace, `[${targetContractName}](${contractData.path})`);
            continue;
          }

          // if it doesn't, then it's most probably a link to an element in the same file
          elementSignature = targetContractName;
          targetContractName = contractName;
        }

        // find the target contract and element signature to replace the broken link
        const targetSignature = signaturesPerFile.get(targetContractName)?.signatures[elementSignature];
        if (targetSignature) {
          isRewriteNecessary = true;
          content = content.replaceAll(stringToReplace, `[${targetSignature.name}](${targetSignature.href})`);
        } else {
          console.warn(`Could not find signature for link ${stringToReplace} in ${docFilePath}`);
        }
      }
    }
  }

  // rewrite the file if necessary
  if (isRewriteNecessary) writeFileSync(`${DOCS_MD_PATH}/${docFilePath}`, content);
}

const docFiles = getRelevantDocFiles();
indexContractElements(docFiles);
for (let i = 0; i < docFiles.length; i++) {
  fixDocFile(docFiles[i]);
}
