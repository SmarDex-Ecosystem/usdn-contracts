import type { Address, GetContractReturnType, PublicClient } from 'viem';
import { keccak256, toHex, http, createPublicClient, getContract } from 'viem';
import { IUsdnProtocolAbi } from '../../dist/abi';
import { IOracleMiddlewareAbi } from '../../dist/abi';

const USDN_ADDRESS = '0x0000000000000000000000000000000000000000';
const USDN_PROTOCOL_ADDRESS = '0x0000000000000000000000000000000000000000';
const ORACLE_MIDDLEWARE_ADDRESS = '0x0000000000000000000000000000000000000000';
const SAFE_ADDRESS = '0x1E3e1128F6bC2264a19D7a065982696d356879c5';
const MINTER_ROLE = keccak256(toHex('MINTER_ROLE'));
const REBASER_ROLE = keccak256(toHex('REBASER_ROLE'));
const DEFAULT_ADMIN_ROLE = keccak256('0x00');

async function main() {
  const client = createPublicClient({
    transport: http('rpcUrl'), // TODO : replace with actual rpc url
  });

  const protocol = getContract({
    address: USDN_PROTOCOL_ADDRESS,
    abi: IUsdnProtocolAbi,
    client: client,
  });
  const oracleMiddleware = getContract({
    address: ORACLE_MIDDLEWARE_ADDRESS,
    abi: IOracleMiddlewareAbi,
    client: client,
  });

  const { depositAmount, desiredLiqPrice } = await getDepositAmountAndLiqPrice(100n, protocol, oracleMiddleware);
}

async function getDepositAmountAndLiqPrice(
  longAmount: bigint,
  protocol: GetContractReturnType<typeof IUsdnProtocolAbi, PublicClient>,
  oracleMiddleware: GetContractReturnType<typeof IOracleMiddlewareAbi, PublicClient>,
): Promise<{ depositAmount: bigint; desiredLiqPrice: bigint }> {
  const liquidationPenalty = await protocol.read.getLiquidationPenalty();
  const tickSpacing = await protocol.read.getTickSpacing();
  const price = (await oracleMiddleware.simulate.parseAndValidatePrice(['0x', BigInt(Date.now()), 1, '0x'])).result
    .price;

  // we want a leverage of ~2x so we get the current price from the middleware and divide it by two
  const desiredLiqPrice = price / 2n;
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

function batch(safe: Address, transactions: TransactionData[]): TxBatch {
  const allTx: TransactionData[] = [];
  allTx.push(grantUsdnRoleToProtocol(MINTER_ROLE));
  allTx.push(grantUsdnRoleToProtocol(REBASER_ROLE));
  allTx.push(renounceUsdnAdminRoleFromSafe);

  const tx: TxBatch = {
    version: '1.0', // TODO: check version
    chainId: '1',
    createdAt: Date.now(),
    meta: {
      createdFromSafeAddress: safe,
      name: 'Batch',
    },
    transactions: transactions,
  };

  return tx;
}

function createInitializationTx(depositAmount: string, longAmount: string, desiredLiqPrice: string): TransactionData {
  return {
    to: USDN_ADDRESS,
    value: '0',
    data: '0x',
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

function grantUsdnRoleToProtocol(role: string): TransactionData {
  return {
    to: USDN_ADDRESS,
    value: '0',
    data: '0x',
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
      account: USDN_PROTOCOL_ADDRESS,
    },
  };
}

const renounceUsdnAdminRoleFromSafe: TransactionData = {
  to: USDN_ADDRESS,
  value: '0',
  data: '0x',
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
