import { celo, celoSepolia } from "viem/chains";

// "sepolia" para pruebas en Celo Sepolia, "mainnet" para Celo — mismo patron que relayer/src/chain.ts.
export const chain = process.env.NEXT_PUBLIC_CHAIN === "mainnet" ? celo : celoSepolia;

// No se valida aqui a nivel de modulo: Next.js evalua este archivo durante el build/SSR, y ahi
// las variables NEXT_PUBLIC_* del entorno de build pueden no estar presentes todavia. La UI valida
// con isConfigured() y muestra un aviso en vez de romper el build entero.
export const rpcUrl = process.env.NEXT_PUBLIC_RPC_URL ?? "";
export const operatorAddress = (process.env.NEXT_PUBLIC_OPERATOR_ADDRESS ?? "") as `0x${string}`;

export function isConfigured(): boolean {
  return rpcUrl.length > 0 && operatorAddress.length === 42;
}

// Zona por defecto que se muestra en la pantalla de recarga (1 = Urbano, ver VIA_Operator).
export const DEFAULT_ZONE_ID = 1n;

// Bloque de despliegue del operador, para no escanear eventos desde el bloque 0 (ver network-info.md
// sobre el limite de 50,000 bloques por eth_getLogs). Ajusta esto tras cada deploy nuevo.
export const DEPLOY_BLOCK = BigInt(process.env.NEXT_PUBLIC_DEPLOY_BLOCK ?? "0");
