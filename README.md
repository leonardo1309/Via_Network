# Via Network 🚌 🌐

## Description
Via Network is a decentralized physical infrastructure network (DePIN) designed to modernize public transit payments in Latin America. Utilizing ESP32-S3 microcontrollers and RFID technology, Via Network enables real-time, ultra-low-cost fare validation directly on-chain via the Celo network, paving the way for seamless, cash-free commuting.

## Architecture Outline
- **/firmware**: ESP32-S3 firmware for RFID/NFC card reading and secure validation.
- **/backend**: TypeScript service powered by **Viem** for sub-second smart contract interactions.
- **/contracts**: Solidity smart contracts for validator registration and secure transit fare state.

## MiniPay Integration
Designed with a mobile-first approach, natively compatible with MiniPay for seamless user balance management and topping up via stable assets (cUSD/USDC/CELO), with architectural support for local fiat-pegged stablecoins like COPm for local transit pricing.
