# Via Network 🚌

**Cash-free public transit fare payment for Bogotá/Cundinamarca, Colombia — built on Celo.**

[![CI](https://github.com/leonardo1309/Via_Network/actions/workflows/test.yml/badge.svg)](https://github.com/leonardo1309/Via_Network/actions/workflows/test.yml)
[![License: MIT](https://img.shields.io/badge/License-MIT-yellow.svg)](LICENSE)
[![Solidity](https://img.shields.io/badge/Solidity-%5E0.8.20-363636)](src/VIA_Operator.sol)
[![Built on Celo](https://img.shields.io/badge/Built%20on-Celo-FCFF52)](https://celo.org)

## Overview

Via Network is a DePIN (Decentralized Physical Infrastructure Network) project: a physical validator
mounted on a bus reads a passenger's RFID card and authorizes a fare charge that pulls a stablecoin
(**COPm**, Mento's Colombian Peso stablecoin) directly from the passenger's wallet to the transport
company's wallet — no cash, no closed-loop fare card, no custom token to manage.

The validator device signs the authorization locally: the physical tap on the reader is the source of
truth for "this passenger, this bus, this fare," not whichever backend happens to relay the transaction.

## Table of Contents

- [Architecture](#architecture)
- [Prerequisites](#prerequisites)
- [Smart Contracts](#smart-contracts-foundry)
- [Relayer](#relayer)
- [Firmware](#firmware-esp32)
- [Frontend](#frontend-flutter)
- [Networks](#networks)
- [Project Status](#project-status)
- [License](#license)

## Architecture

The repository has four independent subprojects, each with its own toolchain:

| Path | Stack | Purpose |
|---|---|---|
| `src/`, `script/`, `test/` | Foundry / Solidity | The on-chain contract, `VIA_Operator` |
| `firmware/` | C++ / PlatformIO / ESP32 | Physical validator firmware (ESP32 + PN532 RFID reader) |
| `relayer/` | TypeScript / viem / Express | Pays gas on behalf of validators via Celo fee abstraction |
| `frontend/` | Flutter (Dart) | Passenger-facing mobile app *(early prototype — see [Project Status](#project-status))* |

### How a fare gets collected

`VIA_Operator` exposes two ways to charge a fare, both funneling into the same logic — a direct
`transferFrom(passenger, treasury, price)` in the configured payment token (COPm). The contract never
holds passenger funds itself.

1. **`collectFare(user, busId, zoneId)`** — the validator calls this directly and pays its own gas in
   native CELO. Requires `VALIDATOR_ROLE`.
2. **`collectFareWithSig(user, busId, zoneId, nonce, signature)`** — the validator signs an EIP-712
   message off-chain instead of submitting a transaction; the relayer (or anyone) can relay it on-chain
   and pay the gas — in a Celo fee-currency token (e.g. USDm), via Celo's native fee abstraction — but
   cannot fabricate a charge the validator didn't actually sign. This is what lets a large validator
   fleet operate without every device holding native CELO for gas.

`setZonePrice`/`setTreasury` (admin-only) let fares and the receiving wallet change without a redeploy,
and `deactivateBus` revokes a validator's role immediately if a device is lost or compromised.

## Prerequisites

| Tool | Used for | Install |
|---|---|---|
| [Foundry](https://book.getfoundry.sh/getting-started/installation) (`forge`/`cast`/`anvil`) | Smart contracts | `curl -L https://foundry.paradigm.xyz \| bash && foundryup` |
| [Node.js](https://nodejs.org/) 18+ | Relayer | — |
| [PlatformIO Core](https://docs.platformio.org/en/latest/core/installation/index.html) (`pio`) | Firmware | `pip install -U platformio`, or the VS Code extension |
| [Flutter](https://docs.flutter.dev/get-started/install) | Frontend | — |

> On Windows, Foundry and PlatformIO are commonly run from WSL / a Python virtualenv respectively — if
> a command isn't found in your shell, check whether it was installed somewhere else before assuming
> it's missing.

## Smart Contracts (Foundry)

```bash
forge build              # compile
forge test -vvv          # run the test suite
forge fmt --check        # formatting check (CI runs this)
```

Deployment resolves the payment token and treasury per network via `script/HelperConfig.s.sol` — no
addresses are hardcoded. Copy `.env.example` to `.env` and fill in `PRIVATE_KEY` (and `TREASURY_ADDRESS`
for Sepolia/Mainnet — not needed for a local Anvil deploy, which uses a mock token and test treasury
automatically):

```bash
anvil                                                            # local chain, in its own terminal
forge script script/Deploy.s.sol --rpc-url http://localhost:8545 --broadcast   # local
forge script script/Deploy.s.sol --rpc-url celo_sepolia --broadcast --verify   # testnet
```

`rpc_endpoints` and `[etherscan]` for `celo_sepolia` and `celo` are preconfigured in `foundry.toml`.

## Relayer

A minimal Express + [viem](https://viem.sh) service that submits validator-signed fare charges on-chain
and pays gas in a Celo fee-currency token instead of native CELO ([CIP-64](https://github.com/celo-org/celo-proposals/blob/master/CIPs/cip-0064.md) fee abstraction).

```bash
cd relayer
npm install
cp .env.example .env    # RELAYER_PRIVATE_KEY, RPC_URL, OPERATOR_ADDRESS, FEE_CURRENCY_ADDRESS
npm run dev              # tsx watch src/index.ts
```

| Endpoint | Purpose |
|---|---|
| `GET /nonce/:validator` | Next nonce a validator should sign for |
| `POST /collect-fare` | Relays a signed `{user, busId, zoneId, nonce, signature}` fare charge |

## Firmware (ESP32)

ESP32 DevKit V1 + PN532 NFC reader (I2C). Built with [PlatformIO](https://platformio.org).

```bash
cd firmware
cp src/config.example.h src/config.h   # fill in WiFi, RPC, deployed contract address, validator key
pio run -e esp32dev-local -t upload    # or esp32dev-testnet for Celo Sepolia
pio device monitor --port <COMx> --baud 115200
```

The validator's derived address (from `PRIVATE_KEY` in `config.h`) needs `VALIDATOR_ROLE` on the
deployed `VIA_Operator` before it can charge fares:

```bash
cast send <VIA_OPERATOR_ADDRESS> "grantRole(bytes32,address)" $(cast keccak "VALIDATOR_ROLE") <VALIDATOR_ADDRESS> \
  --rpc-url <RPC_URL> --private-key <ADMIN_PRIVATE_KEY>
```

Cryptography (ABI encoding, transaction signing) is handled locally by the [Web3E](https://github.com/AlphaWallet/Web3E)
library; JSON-RPC transport is a small hand-rolled HTTP client, since Web3E's own RPC methods are
TLS-only and don't recognize Anvil's or Celo's chain IDs.

## Frontend (Flutter)

```bash
cd frontend
flutter pub get
flutter run
```

## Networks

Celo migrated to an OP Stack L2 in March 2025. **Alfajores is deprecated** — Celo Sepolia is the current
testnet step before mainnet.

| | Celo Sepolia (testnet) | Celo Mainnet |
|---|---|---|
| Chain ID | `11142220` | `42220` |
| RPC | `https://forno.celo-sepolia.celo-testnet.org` | `https://forno.celo.org` |
| Explorer | [celo-sepolia.blockscout.com](https://celo-sepolia.blockscout.com) | [celoscan.io](https://celoscan.io) |
| Faucet | [faucet.celo.org](https://faucet.celo.org) | — |
| Payment token | USDm `0xdE9e4C3ce781b4bA68120d6261cbad65ce0aB00b` *(stand-in — see note)* | COPm `0x8A567e2aE79CA692Bd748aB832081C45de4041eA` |

> Celo Sepolia has no live Mento v3 COPm deployment yet, so USDm stands in for testing there;
> `HelperConfig.s.sol` resolves the correct token automatically per network.

## Project Status

Actively developed under Celo's Proof of Ship program. Current state, honestly:

- ✅ **Smart contracts** — `VIA_Operator` (direct + EIP-712 relay fare collection), fully tested.
- ✅ **Relayer** — functional fee-abstraction service for `collectFareWithSig`.
- ✅ **Firmware** — validated end-to-end against a live ESP32 + Anvil (`collectFare` direct-call path).
  Signing the EIP-712 message for the relayer path instead of a raw transaction is still open work.
- 🚧 **Frontend** — early prototype; predates the current contract design and needs a rewrite to match
  (COPm balance, relayer-driven fare history) rather than the retired closed-loop token it still targets.

## License

[MIT](LICENSE)
