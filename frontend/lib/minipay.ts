import { createPublicClient, createWalletClient, custom, http } from "viem";
import { chain, rpcUrl } from "./config";

declare global {
  interface Window {
    ethereum?: {
      isMiniPay?: boolean;
      request: (args: { method: string; params?: unknown[] }) => Promise<unknown>;
    };
  }
}

/** true si la pagina corre dentro del WebView de MiniPay. */
export function isMiniPay(): boolean {
  return typeof window !== "undefined" && window.ethereum?.isMiniPay === true;
}

/** Cliente de solo lectura contra el RPC configurado (no depende de una wallet inyectada). */
export function getPublicClient() {
  return createPublicClient({ chain, transport: http(rpcUrl) });
}

/**
 * Cliente de escritura contra la wallet inyectada (MiniPay u otra compatible con window.ethereum).
 * Devuelve null si no hay wallet inyectada — el llamador debe manejar ese caso (fuera de MiniPay,
 * en un navegador de escritorio sin extension, por ejemplo).
 */
export function getWalletClient() {
  if (typeof window === "undefined" || !window.ethereum) return null;
  return createWalletClient({ chain, transport: custom(window.ethereum) });
}
