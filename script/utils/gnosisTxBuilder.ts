import type { Address, GetContractReturnType, Hex, PublicClient } from 'viem';
import {
  keccak256,
  toHex,
  http,
  createPublicClient,
  getContract,
  isAddress,
  pad,
  stringToBytes,
  bytesToHex,
} from 'viem';
import { IUsdnProtocolAbi } from '../../dist/abi';
import { IOracleMiddlewareAbi } from '../../dist/abi';
import { Command } from 'commander';
import { writeFileSync } from 'node:fs';

const SAFE_ADDRESS: Address = '0x1E3e1128F6bC2264a19D7a065982696d356879c5';
const MINTER_ROLE = keccak256(toHex('MINTER_ROLE'));
const REBASER_ROLE = keccak256(toHex('REBASER_ROLE'));
const DEFAULT_ADMIN_ROLE = keccak256('0x00');

main();

async function main() {
  const program = new Command();
  program
    .description('Create a batch transaction for Gnosis Safe to initialize the USDN protocol')
    .requiredOption('-r, --rpc-url <URL>', 'The RPC URL')
    .requiredOption('-p, --protocol <Address>', 'The address of the USDN protocol contract')
    .requiredOption('-l, --long-amount <amount>', 'The wanted long amount')
    .parse(process.argv);

  let USDN_PROTOCOL_ADDRESS: Address;
  const options = program.opts();
  if (isAddress(options.protocol)) {
    USDN_PROTOCOL_ADDRESS = options.protocol;
  } else {
    console.error('Invalid address');
    process.exit(1);
  }

  const client = createPublicClient({
    transport: http(options.rpcUrl),
  });

  try {
    await client.getBlockNumber();
  } catch {
    console.error('Invalid RPC URL');
    process.exit(1);
  }
  const longAmount = BigInt(options.longAmount);

  const protocol = getContract({
    address: USDN_PROTOCOL_ADDRESS,
    abi: IUsdnProtocolAbi,
    client: client,
  });
  const oracleMiddleware = getContract({
    address: await protocol.read.getOracleMiddleware(),
    abi: IOracleMiddlewareAbi,
    client: client,
  });

  const usdnAddress = await protocol.read.getUsdn();
  const { depositAmount, desiredLiqPrice } = await getDepositAmountAndLiqPrice(longAmount, protocol, oracleMiddleware);
  const initializationTx = createInitializationTx(
    usdnAddress,
    depositAmount.toString(),
    longAmount.toString(),
    desiredLiqPrice.toString(),
  );
  const batchTx = batch(usdnAddress, SAFE_ADDRESS, USDN_PROTOCOL_ADDRESS, initializationTx);

  // write to file
  writeFileSync('batch.json', JSON.stringify(batchTx, null, 2));
}

async function getDepositAmountAndLiqPrice(
  longAmount: bigint,
  protocol: GetContractReturnType<typeof IUsdnProtocolAbi, PublicClient>,
  oracleMiddleware: GetContractReturnType<typeof IOracleMiddlewareAbi, PublicClient>,
): Promise<{ depositAmount: bigint; desiredLiqPrice: bigint }> {
  const liquidationPenalty = await protocol.read.getLiquidationPenalty();
  const tickSpacing = await protocol.read.getTickSpacing();
  const price = (await oracleMiddleware.simulate.parseAndValidatePrice([pad('0x'), BigInt(Date.now()), 1, '0x'])).result
    .price;

  // we want a leverage of ~2.5x so we get the current price from the middleware and divide it by two
  const desiredLiqPrice = (price * 3n) / 5n;
  // get the liquidation price with the tick rounding
  const liqPriceWithoutPenalty = await protocol.read.getLiqPriceFromDesiredLiqPrice([
    desiredLiqPrice,
    price,
    0n,
    { hi: 0n, lo: 0n },
    tickSpacing,
    liquidationPenalty,
  ]);
  // get the total exposure of the wanted long position
  const positionTotalExpo = (longAmount * price) / (price - liqPriceWithoutPenalty);
  // get the amount to deposit to reach a balanced state
  const depositAmount = positionTotalExpo - longAmount;

  return {
    depositAmount: depositAmount,
    desiredLiqPrice: desiredLiqPrice,
  };
}

function batch(
  usdnAddress: Address,
  safe: Address,
  usdnProtocolAddress: Address,
  initializationTx: TransactionData,
): TxBatch {
  const allTx: TransactionData[] = [];
  allTx.push(grantUsdnRoleToProtocol(usdnAddress, MINTER_ROLE, usdnProtocolAddress));
  allTx.push(grantUsdnRoleToProtocol(usdnAddress, REBASER_ROLE, usdnProtocolAddress));
  allTx.push(renounceUsdnAdminRoleFromSafe(usdnAddress));
  allTx.push(initializationTx);

  const tx: TxBatch = {
    version: '1.0', // TODO: check version
    chainId: '1',
    createdAt: Date.now(),
    meta: {
      createdFromSafeAddress: safe,
      name: 'Batch',
    },
    transactions: allTx,
  };

  return tx;
}

function createInitializationTx(
  usdnAddress: Address,
  depositAmount: string,
  longAmount: string,
  desiredLiqPrice: string,
): TransactionData {
  return {
    to: usdnAddress,
    value: '0',
    data: '',
    contractMethod: {
      name: 'initialize',
      payable: true,
      inputs: [
        {
          internalType: 'uint128',
          name: 'depositAmount',
          type: 'uint128',
        },
        {
          internalType: 'uint128',
          name: 'longAmount',
          type: 'uint128',
        },
        {
          internalType: 'uint128',
          name: 'desiredLiqPrice',
          type: 'uint128',
        },
        {
          internalType: 'bytes',
          name: 'currentPriceData',
          type: 'bytes',
        },
      ],
    },
    contractInputsValues: {
      depositAmount: depositAmount,
      longAmount: longAmount,
      desiredLiqPrice: desiredLiqPrice,
      currentPriceData: '0x',
    },
  };
}

function grantUsdnRoleToProtocol(usdnAddress: Address, role: string, usdnProtocolAddress: Address): TransactionData {
  return {
    to: usdnAddress,
    value: '0',
    data: '',
    contractMethod: {
      name: 'grantRole',
      payable: false,
      inputs: [
        {
          internalType: 'bytes32',
          name: 'role',
          type: 'bytes32',
        },
        {
          internalType: 'address',
          name: 'account',
          type: 'address',
        },
      ],
    },
    contractInputsValues: {
      role: role,
      account: usdnProtocolAddress,
    },
  };
}

function renounceUsdnAdminRoleFromSafe(usdnAddress: Address): TransactionData {
  return {
    to: usdnAddress,
    value: '0',
    data: '',
    contractMethod: {
      name: 'renounceRole',
      payable: false,
      inputs: [
        {
          internalType: 'bytes32',
          name: 'role',
          type: 'bytes32',
        },
        {
          internalType: 'address',
          name: 'account',
          type: 'address',
        },
      ],
    },
    contractInputsValues: {
      role: DEFAULT_ADMIN_ROLE,
      account: SAFE_ADDRESS,
    },
  };
}

/////////////////////////////

interface TxBatch {
  version: string;
  chainId: string;
  createdAt: number;
  meta: TxMeta;
  transactions: TransactionData[];
}

interface TxMeta {
  //   txBuilderVersion?: string;
  createdFromSafeAddress: Address;
  name: string;
}

interface TransactionData {
  to: Address;
  value: string;
  data: string;
  contractMethod: ContractMethod;
  contractInputsValues: { [key: string]: string };
}

interface ContractMethod {
  inputs: ContractInput[];
  name: string;
  payable: boolean;
}

interface ContractInput {
  internalType: string;
  name: string;
  type: string;
  components?: ContractInput[];
}

//////////////////////
