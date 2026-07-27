import "dotenv/config";
import { createPublicClient, createWalletClient, http } from "viem";
import { privateKeyToAccount } from "viem/accounts";
import { celo, celoSepolia } from "viem/chains";

function requireEnv(name: string): string {
  const value = process.env[name];
  if (!value) {
    throw new Error(`Falta la variable de entorno ${name} (ver relayer/.env.example)`);
  }
  return value;
}

export const chain = process.env.CHAIN === "mainnet" ? celo : celoSepolia;

export const account = privateKeyToAccount(
  requireEnv("RELAYER_PRIVATE_KEY") as `0x${string}`
);

export const operatorAddress = requireEnv("OPERATOR_ADDRESS") as `0x${string}`;
export const feeCurrencyAddress = requireEnv("FEE_CURRENCY_ADDRESS") as `0x${string}`;

const rpcUrl = requireEnv("RPC_URL");

export const publicClient = createPublicClient({
  chain,
  transport: http(rpcUrl),
});

export const walletClient = createWalletClient({
  account,
  chain,
  transport: http(rpcUrl),
});
