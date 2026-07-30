import { createConfig, http } from "wagmi";
import { celo, celoSepolia } from "wagmi/chains";
import { injected } from "wagmi/connectors";
import { chain, rpcUrl } from "./config";

// Un solo connector (injected) — MiniPay expone window.ethereum directamente y no soporta
// selectores multi-wallet (RainbowKit rompe el flujo "zero-click connect" que exige MiniPay).
//
// `chain` (de config.ts) es un tipo union (celo | celoSepolia) resuelto en runtime desde
// NEXT_PUBLIC_CHAIN, asi que transports debe cubrir ambos ids a nivel de tipos aunque solo
// uno se use realmente en runtime.
export const wagmiConfig = createConfig({
  chains: [chain],
  connectors: [injected()],
  transports: {
    [celo.id]: http(rpcUrl),
    [celoSepolia.id]: http(rpcUrl),
  },
  ssr: true,
});

// Registra el tipo concreto de wagmiConfig para que los hooks (useSendTransaction, etc.) infieran
// los campos especificos de la cadena de Celo (feeCurrency) en vez de un tipo Config generico.
declare module "wagmi" {
  interface Register {
    config: typeof wagmiConfig;
  }
}
