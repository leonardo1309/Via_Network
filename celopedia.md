# Celopedia - Celo Developer Rules for Copilot

## Tech Stack
- Always write blockchain code using **Viem** and **TypeScript**.
- Do NOT use legacy libraries (ethers.js or web3.js).
- For React/Next.js frontends, use **Wagmi** hooks.

## MiniPay & Mini App UX Rules
- Target Wallet: MiniPay (Opera Mini).
- User Identity: Accounts are mapped to phone numbers, not raw hexadecimal addresses.
- Crypto Jargon Ban: In UI strings, never use words like "Gas" or "Tokens". Use "Network fee" and "Digital Pesos (cCOP)" or "Digital Dollars".

## Native Fee Abstraction
- Celo allows paying gas fees directly with stablecoins.
- When sending a transaction with Viem, always include the `feeCurrency` parameter with the official token contract address.