import type { Address, GetContractReturnType, PublicClient } from 'viem';
import { http, createPublicClient, getContract, pad } from 'viem';
import { IUsdnProtocolAbi } from '../../dist/abi';
import { IOracleMiddlewareAbi } from '../../dist/abi';
import { Command } from 'commander';
import { writeFileSync } from 'node:fs';

const SAFE_ADDRESS: Address = '0x1E3e1128F6bC2264a19D7a065982696d356879c5';
const USDN_PROTOCOL_ADDRESS: Address = '0x656cB8C6d154Aad29d8771384089be5B5141f01a';

main();

async function main() {
  const program = new Command();
  program
    .description('Create a batch transaction for Gnosis Safe to initialize the USDN protocol')
    .requiredOption('-r, --rpc-url <URL>', 'The RPC URL')
    .requiredOption('-t, --total-amount <amount>', 'The total amount to initiate the protocol')
    .parse(process.argv);

  const options = program.opts();

  const client = createPublicClient({
    transport: http(options.rpcUrl),
  });

  try {
    await client.getBlockNumber();
  } catch {
    console.error('Invalid RPC URL');
    process.exit(1);
  }

  const totalAmount = BigInt(options.totalAmount);

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

  const { depositAmount, longAmount, desiredLiqPrice } = await getAmountsAndLiqPrice(
    totalAmount,
    protocol,
    oracleMiddleware,
  );
  const initializationTx = createInitializationTx(
    depositAmount.toString(),
    longAmount.toString(),
    desiredLiqPrice.toString(),
  );

  const tx: TxBatch = {
    version: '1.0',
    chainId: '1',
    createdAt: Date.now(),
    meta: {
      createdFromSafeAddress: SAFE_ADDRESS,
      name: 'Initialization of the USDN protocol',
    },
    transactions: [initializationTx],
  };

  writeFileSync('initialization.json', JSON.stringify(tx, null, 2));
}

async function getAmountsAndLiqPrice(
  totalAmount: bigint,
  protocol: GetContractReturnType<typeof IUsdnProtocolAbi, PublicClient>,
  oracleMiddleware: GetContractReturnType<typeof IOracleMiddlewareAbi, PublicClient>,
): Promise<{ depositAmount: bigint; longAmount: bigint; desiredLiqPrice: bigint }> {
  const liquidationPenalty = await protocol.read.getLiquidationPenalty();
  const tickSpacing = await protocol.read.getTickSpacing();

  const price = (await oracleMiddleware.simulate.parseAndValidatePrice([pad('0x'), BigInt(Date.now()), 1, '0x'])).result
    .price;

  // we want a leverage of ~2.5x
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

  // longAmount = (totalAmount / price) * (price - liqPriceWithoutPenalty)
  const longAmount = (((totalAmount * 10n ** 18n) / price) * (price - liqPriceWithoutPenalty)) / 10n ** 18n;
  const depositAmount = totalAmount - longAmount;

  return {
    depositAmount: depositAmount,
    longAmount: longAmount,
    desiredLiqPrice: liqPriceWithoutPenalty,
  };
}

function createInitializationTx(depositAmount: string, longAmount: string, desiredLiqPrice: string): TransactionData {
  return {
    to: USDN_PROTOCOL_ADDRESS,
    value: '0',
    data: '',
    contractMethod: {
      name: 'initialize',
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

/* -------------------------------------------------------------------------- */
/*                                    Types                                   */
/* -------------------------------------------------------------------------- */
interface TxBatch {
  version: string;
  chainId: string;
  createdAt: number;
  meta: TxMeta;
  transactions: TransactionData[];
}

interface TxMeta {
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
}

interface ContractInput {
  internalType: string;
  name: string;
  type: string;
}
