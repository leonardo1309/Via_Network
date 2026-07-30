import { createWalletClient, custom } from "viem";
import { chain } from "./config";

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

/** true si hay algun proveedor EIP-1193 inyectado (MiniPay u otro, p.ej. una extension de escritorio). */
export function hasInjectedProvider(): boolean {
  return typeof window !== "undefined" && window.ethereum !== undefined;
}

/**
 * Cliente de escritura directo (viem + custom(window.ethereum)), fuera de wagmi.
 * Necesario para transacciones con feeCurrency: wagmi's useSendTransaction envio la tx como legacy
 * sin feeCurrency dentro de MiniPay (confirmado — el nodo pidio CELO nativo, no la stablecoin), pero
 * un walletClient construido asi si aplica el formatter CIP-64 de la chain de Celo correctamente.
 * Mismo patron que minipay-guide.md (Celo skill) usa para "Send Stablecoin Payment".
 */
export function getWalletClient() {
  if (typeof window === "undefined" || !window.ethereum) return null;
  return createWalletClient({ chain, transport: custom(window.ethereum) });
}
