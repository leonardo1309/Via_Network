# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project overview

Via Network is a DePIN (Decentralized Physical Infrastructure Network) project for public transit fare
payment in Bogotá/Cundinamarca, Colombia, built on Celo. A physical validator (ESP32 + PN532 RFID reader)
mounted on a bus reads a passenger's RFID card and authorizes a fare charge that pulls a stablecoin
(COPm) directly from the passenger's wallet to the transport company's wallet — no cash, no closed-loop
token.

The repo has four independent subprojects that don't share a build system:

| Path | Stack | Purpose |
|---|---|---|
| `src/`, `script/`, `test/` (repo root) | Foundry / Solidity | The on-chain contract (`VIA_Operator`) |
| `firmware/` | C++ / PlatformIO / ESP32 | Physical validator firmware |
| `relayer/` | TypeScript / viem / Express | Pays gas on behalf of validators via Celo fee abstraction |
| `frontend/` | Next.js / wagmi / viem / TypeScript | "VIA Pay" — passenger-facing MiniPay Mini App |

`backend/` at the repo root is an empty leftover directory from an earlier plan — the real TypeScript
service is `relayer/`, not `backend/`. Don't add code to `backend/`.

## Commands

### Smart contracts (Foundry) — run from repo root

Foundry (`forge`/`cast`/`anvil`) is **not on PATH in a native Windows shell** on this machine — the user
runs it from WSL. If `forge` isn't found, don't conclude Foundry is missing; try invoking it through WSL,
e.g. (from Git Bash, disabling its path-mangling and calling the binary directly since login-shell PATH
sourcing doesn't pick it up non-interactively):

```bash
MSYS2_ARG_CONV_EXCL="*" wsl /home/l30/.foundry/bin/forge build --root '/mnt/c/Users/ASUS/Documents/VIA Network'
MSYS2_ARG_CONV_EXCL="*" wsl /home/l30/.foundry/bin/forge test --root '/mnt/c/Users/ASUS/Documents/VIA Network' -vv
```

Otherwise, standard Foundry commands apply:

```bash
forge build                              # compile
forge build --sizes                      # compile + contract size report (used in CI)
forge fmt --check                        # formatting check (used in CI, run forge fmt to fix)
forge test -vvv                          # run all tests
forge test --match-test test_CollectFareWithSig_Success -vvv   # run a single test
```

CI (`.github/workflows/test.yml`) runs exactly: `forge fmt --check`, `forge build --sizes`, `forge test -vvv`.

Deploying `VIA_Operator` (`script/Deploy.s.sol`) requires `TREASURY_ADDRESS` as an env var (see
`.env.example`). The payment token address is **not** an env var — `script/HelperConfig.s.sol`
resolves it from `block.chainid` (see Architecture below).

**Signing key**: `Deploy.s.sol` branches on `block.chainid` — on Anvil (`31337`) it signs with
`PRIVATE_KEY` from `.env` (fine, it's just one of Anvil's public throwaway test keys); on any real
network it calls `vm.startBroadcast()` with no arguments and expects `--account <name> --sender
<address>` on the CLI instead, so a real private key never sits in `.env` in plaintext. Import a
key into an encrypted keystore once with `cast wallet import <name> --interactive` (prompts for the
key + an encryption password, stores it under `~/.foundry/keystores/`), then:

```bash
forge script script/Deploy.s.sol --rpc-url celo_sepolia --account via-deployer --sender <ADDRESS> --broadcast --verify
```

`rpc_endpoints` and `[etherscan]` for `celo_sepolia` (11142220) and `celo` (42220) are already configured
in `foundry.toml`.

### Relayer (`relayer/`)

```bash
npm install
npm run dev        # tsx watch src/index.ts
npm run start       # run once
npm run typecheck   # tsc --noEmit
npm run build        # tsc -> dist/
```

Requires `relayer/.env` (see `relayer/.env.example`): `RELAYER_PRIVATE_KEY`, `CHAIN`, `RPC_URL`,
`OPERATOR_ADDRESS`, `FEE_CURRENCY_ADDRESS`, `PORT`.

### Firmware (`firmware/`, PlatformIO)

```bash
pio run -e esp32dev-local          # default env, points at a local Anvil node
pio run -e esp32dev-testnet        # Celo Sepolia profile
pio run -e esp32dev-local -t upload
pio device monitor
```

Requires `firmware/src/config.h` (gitignored — copy from `firmware/src/config.example.h` and fill in
real WiFi/RPC/key values; it holds a plaintext private key and WiFi credentials).

### Frontend (`frontend/`, Next.js MiniPay Mini App)

```bash
cd frontend
npm install
cp .env.local.example .env.local   # NEXT_PUBLIC_RPC_URL, NEXT_PUBLIC_OPERATOR_ADDRESS
npm run dev                        # then expose via ngrok to test inside MiniPay — see below
npm run build && npm run lint
```

Uses **wagmi** (`injected()` connector only — no RainbowKit, whose multi-wallet selector modal
breaks MiniPay's required zero-click auto-connect) + `@tanstack/react-query`. An earlier version of
this project avoided wagmi entirely, reasoning that MiniPay's "2MB" figure was a hard Mini App
bundle cap — that's wrong: the 2MB figure is a marketing stat about the MiniPay **host app**, not a
documented Mini App bundle limit (checked directly against `docs.minipay.xyz`'s best-practices and
deployment pages, neither of which mention any such cap). MiniPay's own best-practices examples use
wagmi hooks. `lib/wagmi.ts` registers the app's `Config` type via TypeScript module augmentation
(`declare module "wagmi" { interface Register { config: typeof wagmiConfig } }`) — without this,
wagmi's hooks fall back to a generic `Config` type and lose Celo's chain-specific `feeCurrency`
field on transaction params. `useWriteContract` does **not** expose `feeCurrency` at all (not in its
parameter type even with the chain registered), and **`useSendTransaction` accepts `feeCurrency` at
the type level but silently drops it at runtime inside MiniPay** — confirmed on a real device: it
submits a plain legacy tx demanding native CELO instead of the requested fee currency. The working
fix was to stop using wagmi for this one call and build a plain
`createWalletClient({ chain, transport: custom(window.ethereum) })` directly (see
`lib/minipay.ts`'s `getWalletClient()`, used from `app/page.tsx`'s `topUp()`) — matching the exact
pattern in the Celo skill's `minipay-guide.md` "Send Stablecoin Payment" example. wagmi is still used
for connection state (`useAccount`/`useConnect`) and all reads (`useReadContract`/`useReadContracts`).
`lib/config.ts` reads `NEXT_PUBLIC_*` env vars **lazily** (not at module scope) — Next.js evaluates
that file during the build/SSR static-generation pass, and throwing there breaks the build even
though the page itself is `"use client"`. `isConfigured()` gates the UI instead.

MiniPay requires a physical device and HTTPS — `localhost` doesn't work. **Test against a production
build (`npm run build && npm run start`), never `npm run dev`** — confirmed empirically that Next's
dev server (Turbopack HMR/Fast Refresh) breaks React re-rendering inside MiniPay's WebView: the app
paints its initial state fine (proving hydration itself succeeds) but every subsequent `setState`
silently fails to commit, freezing the UI on whatever rendered first (e.g. permanently stuck on
"Conectando…") even though the underlying JS (timers, `window.ethereum` access) keeps running
correctly underneath. This was confirmed by comparing React state against a plain `setInterval` +
raw `textContent` counter injected outside React — the counter kept advancing while React's own
output never changed. The dev server's `/_next/webpack-hmr` WebSocket also fails outright over an
ngrok tunnel (visible in ngrok's request log as repeated `status_code: 0` upgrade attempts), which
is the likely trigger. Switching to a production build resolved it completely — the passenger
connected, balance/allowance loaded, and the UI updated normally. MiniPay's own WebView is a release
build with `setWebContentsDebuggingEnabled` off (no `chrome://inspect` entry, even with the device
authorized via `adb`), so this had to be diagnosed via a temporary in-page error catcher
(`window.onerror`/`unhandledrejection` writing to a plain DOM node via a `beforeInteractive`
`next/script`) rather than remote DevTools — that scaffolding was removed once the cause was found,
except for the retry loop it led to (below).

```bash
npm run build && npm run start   # or PORT=3001 npm run start to run alongside `next dev`
npx ngrok http 3000              # (or 3001, matching whatever port start used)
```
then open the ngrok HTTPS URL inside MiniPay (Settings → About → tap Version 7× → Developer
Settings → Load Test Page).

`app/page.tsx`'s wallet-detection effect retries for ~4s (polling every 200ms) instead of checking
`window.ethereum` once on mount — some wallets inject their provider a moment after the page's first
render, and a single synchronous check can race that and permanently report "no wallet".

## Architecture

### `VIA_Operator.sol` — the only remaining contract

`VIAToken` (a closed-loop ERC20 the operator used to mint/burn) was **retired**. Fares are now paid in
a real stablecoin pulled directly from the passenger:

- `i_paymentToken` (immutable, set at deploy) — real COPm on both mainnet and Celo Sepolia (see
  Networks below). Celo Sepolia has no Mento **v3** COPm deployment, but the **v2** one is live and
  has real liquidity (confirmed via a manual Mento V2 swap, `v2-app.mento.org` — the newer V3 app at
  `app.mento.org` has little/no liquidity yet on testnet for most pairs).
- `s_treasury` (mutable, admin-settable via `setTreasury`) — the transport company's wallet. The
  contract **never holds passenger funds**; every charge is a direct
  `i_paymentToken.safeTransferFrom(user, s_treasury, price)`. Passengers must have pre-approved
  `VIA_Operator` to pull from their balance.
- `s_zonePrices` — per-zone fare, admin-settable via `setZonePrice`.

Two entry points funnel into the same private `_collectFare`:
- `collectFare(user, busId, zoneId)` — `onlyRole(VALIDATOR_ROLE)`, the validator calls this directly
  and pays its own gas in native CELO.
- `collectFareWithSig(user, busId, zoneId, nonce, signature)` — **permissionless caller**. The validator
  signs an EIP-712 message (`CollectFare(user,busId,zoneId,nonce)`) off-chain; anyone (the relayer) can
  submit it on-chain and pay the gas, but `ecrecover` + `hasRole(VALIDATOR_ROLE, signer)` + a per-signer
  nonce mean the relayer can only relay a charge a real validator actually authorized — it cannot
  fabricate one. This is the deliberate trust model: the physical device (which saw the RFID tap) is the
  source of authorization, not whoever pays gas.

`deactivateBus` revokes `VALIDATOR_ROLE` for incident response (e.g. a suspected stolen/compromised
validator).

Solidity in this repo follows the **Patrick Collins / Cyfrin Updraft style** — always apply this, not
just to `VIA_Operator.sol`:
- Layout: license/pragma → imports → custom errors → contract (type declarations → state vars → events
  → modifiers → functions); functions ordered constructor → external → public → internal → private,
  view/pure last in each group.
- Naming: `s_` prefix for mutable storage, `i_` for immutables, `SCREAMING_SNAKE_CASE` constants, leading
  `_` on internal/private functions and their params.
- Custom errors (`VIA_Operator__Reason()`), not `require(cond, "string")`.
- Full NatSpec (`@title`/`@notice`/`@dev` on the contract, `@param`/`@return` on external/public
  functions).
- State is `private` with explicit `getXxx()` getters rather than `public` auto-getters (keeps the ABI
  name stable regardless of the `s_`/`i_` prefix).
- `forge-lint` (built into `forge build`) will flag the `s_`/`i_` naming as non-default — that's
  intentional, don't "fix" it back to mixedCase.

### `HelperConfig.s.sol` — the Patrick Collins network-config pattern

`script/Deploy.s.sol` does **not** read the payment token address from an env var. Instead it deploys
`HelperConfig` (also a `Script`) and reads `helperConfig.activeNetworkConfig()`, a
`struct NetworkConfig { address paymentToken; address treasury; }`. `HelperConfig`'s constructor
branches on `block.chainid`:
- `42220` (Celo Mainnet) → `getCeloMainnetConfig()`, hardcoded COPm address.
- `11142220` (Celo Sepolia) → `getCeloSepoliaConfig()`, hardcoded COPm address (the Mento v2 one).
- anything else (Anvil, `31337`) → `getOrCreateAnvilConfig()`, which deploys a fresh
  `test/mocks/MockPaymentToken.sol` (a bare-bones mintable ERC20) and caches it in
  `activeNetworkConfig` so a second call in the same run doesn't redeploy it.

`treasury` still comes from the `TREASURY_ADDRESS` env var on mainnet/Sepolia (it's real business data,
not a chain constant) but defaults to a well-known Anvil test account locally, so `forge script
script/Deploy.s.sol` works out of the box against a local chain with zero env vars set. The mock lives
in `test/mocks/` (not `script/`) so both `HelperConfig` and `VIA_NetworkTest.t.sol` import the same one
instead of duplicating it.

### Relayer (`relayer/`) — fee abstraction (CIP-64)

A minimal Express + viem service (`src/index.ts`, `src/chain.ts`, `src/abi.ts`) that:
- `GET /nonce/:validator` — reads `VIA_Operator.getNonce` so a validator knows what nonce to sign next.
- `POST /collect-fare` — takes `{user, busId, zoneId, nonce, signature}`, encodes a call to
  `collectFareWithSig`, and submits it via `walletClient.sendTransaction({ ..., feeCurrency })`. The
  relayer's wallet pays gas in `FEE_CURRENCY_ADDRESS` (a Celo CIP-64 fee-currency token, e.g. USDm),
  **not native CELO** — this is Celo's native gas abstraction, viem supports it natively, ethers.js/web3.js
  do not (see celopedia.md rules below).
- `chain.ts` picks `celo` vs `celoSepolia` (viem's bundled chain defs) from the `CHAIN` env var.

### Firmware (`firmware/`) — why it splits crypto from RPC transport

Board: ESP32 DevKit V1 today (target migration: ESP32-S3). Uses the **Web3E** Arduino library, but only
for offline cryptography — `Contract::SetupContractData` (ABI encoding), `Contract::SignTransaction`
(local signing), `KeyID` (address derivation). It deliberately does **not** use Web3E's own
`Web3::Eth*()` RPC methods, because those are structurally broken for this project:
- `Web3::exec()` always opens a `WiFiClientSecure` (TLS-only) — no plain HTTP, so it can't talk to a
  local Anvil node.
- `selectHost()` resolves the RPC host from a hardcoded table keyed by chain ID (`nodes.h`) that has
  **no entry for 31337 (Anvil) or any Celo chain** — falls through to an empty host.
- Its RLP encoder (`Contract::RlpEncode`) only builds **legacy (type-0) transactions** (6 fields +
  EIP-155 chain ID) — there's no way to express Celo's CIP-64 `feeCurrency` field. This is why fee
  abstraction lives in the relayer, not the firmware.

So `main.cpp` implements its own tiny JSON-RPC client (`rpcCall()` via `HTTPClient`) against
`RPC_HOST:RPC_PORT` from `config.h`, and uses Web3E only for signing.

`main.cpp`'s `collectFare()` (renamed from the old `cobrarPasaje()`) now signs and submits a legacy tx
calling the real `collectFare(address,uint256,uint256)` directly — validated end-to-end against a live
ESP32 + a real Celo Sepolia deploy (real `FarePaid` event, real ERC20 `Transfer`, confirmed via
`eth_getLogs` on the deployed contract, not just a tx hash). It still calls the contract directly
(`onlyRole(VALIDATOR_ROLE)`, pays its own gas in native CELO) rather than going through the relayer's
`collectFareWithSig` meta-tx path — that rewrite (sign EIP-712, POST to `/collect-fare`) is still future
work. Web3E's signing primitives (`Crypto::Keccak256` + the low-level `Sign` call) are reusable for it
since EIP-712 ultimately signs a keccak256 digest the same way a raw tx does.

**`GAS_PRICE` in `config.h` is a hardcoded constant and *will* go stale** — hit this directly on a real
device against Celo Sepolia: `GAS_PRICE` was 20 Gwei while the network's actual current price had
drifted to 52.5 Gwei. The signed tx was still fully valid (correct signature, correct recovered sender,
correct chain ID, correct calldata — verified independently with viem's `parseTransaction` +
`recoverTransactionAddress`) and the RPC happily accepted it (`eth_sendRawTransaction` returned a real
hash, logged as `[ÉXITO]`), but it just sat under-priced in the mempool indefinitely with no error ever
surfacing back — `eth_getTransactionReceipt` kept returning `null` and the account's nonce never
advanced. **A tx being accepted by the RPC is not proof it will ever be mined** — for a legacy/manually-
signed tx specifically, check for a receipt (or the nonce advancing) before trusting `[ÉXITO]`. Fixed by
`getNonceAndGasPrice()`, which calls `eth_gasPrice` (batched together with the nonce fetch, see below)
before every `collectFare()` and signs with that value **+20%** headroom, falling back to the
`GAS_PRICE` constant only if the RPC call itself fails.

**`getNonceAndGasPrice()` batches the nonce + gas price fetch into one JSON-RPC array request**
(`[{...eth_getTransactionCount...},{...eth_gasPrice...}]` in a single POST) instead of two sequential
`rpcCall()`s — each call is a full TLS handshake from the ESP32 over Wi-Fi, which is the dominant
source of the tap-to-confirmation delay (not the PN532 — a MIFARE read is sub-second even on a cheap
module). `extractQuotedJsonField()` gained an optional `searchFrom`/`endPosOut` pair so the same
`"result"` key can be pulled out twice from one batch response, in order, without a full JSON parser.

**Real crash found while adding the batch call, in our own code (not Web3E) — a C++ destruction-order
bug already latent in `rpcCall()` too**: both `rpcCall()` and `getNonceAndGasPrice()` declared
`HTTPClient http` at the top of the function and `WiFiClientSecure client` *nested inside* the
`if (RPC_USE_TLS)` block. `http.begin(client, url)` stores a reference to `client`; C++ destroys
locals in reverse declaration order, so when the inner block's `}` closes, `client` — sitting in a
narrower scope — is destroyed *before* the outer `http` is, at the end of the whole function.
`HTTPClient`'s destructor then dereferences the now-dead `client` reference, reading freed stack
memory. Confirmed on a real device with `xtensa-esp32-elf-addr2line` against the build's `.elf`:
`Guru Meditation Error (LoadProhibited)` inside `~HTTPClient()`, called from `getNonceAndGasPrice()`
right after a tap — the ESP32 silently rebooted mid-transaction with no error ever reaching Serial,
which is why it looked identical to "nothing happened" until the full (unfiltered) boot log was
captured. Fix: declare `client` in the **same, outer scope as `http`, before it** — reverse-order
destruction then tears down `http` first (while `client` is still alive) and `client` after. Watch
for this exact shape (`HTTPClient` + `WiFiClientSecure` where one is nested tighter than the other)
in any future networking code here.

**Two real bugs found in vendored Web3E, patched in `.pio/libdeps/*/Web3E/src/Contract.cpp` (all three
PlatformIO envs) — these live in a gitignored, fetched dependency, so they're silently lost on any clean
libdeps reinstall (`pio pkg install`, CI, a fresh clone) and must be reapplied. Consider reporting
upstream or vendoring a patched fork if this keeps biting:**
- `SetupContractData`'s `char tmp[strlen(func)]` is missing the `+1` for the null terminator —
  guaranteed one-byte stack overflow on every call, regardless of signature length. Fix: `strlen(func) + 1`.
- `RlpEncodeForRawTransaction` builds the tx's `R`/`S` signature components as fixed 32-byte arrays and
  RLP-encodes them as-is. RLP requires **minimal/canonical** integer encoding (no leading `0x00` byte);
  since R/S are essentially random, ~1/256 of real signatures have a leading zero byte, and Anvil/revm
  rejects the resulting transaction with `"Failed to decode transaction"`. This is why a probabilistic
  fraction of taps fail — it has nothing to do with payload size or param count. Fix: strip leading zero
  bytes from `R` and `S` before RLP-encoding them (mirroring what `export_bits_truncate()` already does
  for `V`/`value`, which is why those two fields were never affected).

### Frontend (`frontend/`) — "VIA Pay", a MiniPay Mini App

Replaced the original Flutter app entirely (deleted, not migrated — it predated the current
`VIA_Operator`/COPm design and there was nothing worth carrying over). Passengers never sign
`collectFareWithSig` — that's the validator's job (see firmware/relayer above) — so the Mini App's
only on-chain write is a plain `approve()`, which is fully compatible with MiniPay's hard block on
`personal_sign`/`eth_signTypedData`.

- `lib/config.ts` — chain (`celoSepolia`/`celo` from `NEXT_PUBLIC_CHAIN`), RPC URL, and
  `VIA_Operator` address from env vars, read lazily (see Commands above for why).
- `lib/wagmi.ts` — `wagmiConfig` (single chain, `injected()` connector, `http(rpcUrl)` transport)
  plus the `Register` module augmentation described above.
- `app/providers.tsx` — client-component wrapper (`WagmiProvider` + `QueryClientProvider`),
  mounted once in `app/layout.tsx` around `{children}`.
- `lib/minipay.ts` — `isMiniPay()` detection and `hasInjectedProvider()`; no longer builds viem
  clients directly (wagmi/`usePublicClient()` owns that now).
- `lib/abi.ts` — the minimal ERC20 fragment (balance/allowance/approve/decimals/symbol) plus the
  `VIA_Operator` fragment the passenger side actually needs (`getPaymentToken`, `getZonePrice`, the
  `FarePaid` event) — deliberately excludes `collectFare*`.
- `app/page.tsx` — zero-click auto-connect inside MiniPay via `useConnect`/`useAccount` (manual
  "Conectar" button only renders when `!isMiniPay()`, so it never appears inside MiniPay even if
  auto-connect fails, plus a ~4s retry loop polling for `window.ethereum` — some wallets inject it a
  moment after first render, not before); balance/allowance/zone-price reads via
  `useReadContract`/`useReadContracts`; a bounded top-up (`approve()` for exactly N rides' worth,
  never `type(uint256).max` — see the COPm security discussion this repo's history covers); recent-
  fares history read from `FarePaid` logs via `usePublicClient().getLogs` (kept as a plain viem call
  — wagmi has no clean hook for an arbitrary historical block-range log query). Header logo is
  `public/logo.png`; footer links to `/tos` and `/privacy` (drafted, pending legal review) and a
  Telegram support handle. Tapping the truncated account address copies the full address to the
  clipboard (MiniPay only allows truncated as primary display, but the full value still needs to be
  reachable for e.g. sending funds to it from another wallet).

  **The top-up transaction does NOT use wagmi's `useSendTransaction`** — confirmed on a real device
  that it silently drops `feeCurrency` and submits a plain legacy tx requiring native CELO (which
  MiniPay hides and passengers don't hold), even with the `wagmi` `Register` module augmentation in
  place. Fixed by calling `lib/minipay.ts`'s `getWalletClient()` (a `createWalletClient({ chain,
  transport: custom(window.ethereum) })` built directly, bypassing wagmi for this one call) and its
  `.sendTransaction({ ..., feeCurrency })` — the same pattern `minipay-guide.md`'s own "Send
  Stablecoin Payment" example uses. wagmi is still used for connection state and all reads.

  **`feeCurrency` must be `MINIPAY_FEE_CURRENCY` (USDm), never the payment token (COPm)** — also
  confirmed on a real device. COPm is a legitimate fee currency at the Celo protocol level
  (registered in Celo Sepolia's `FeeCurrencyDirectory`, `0x9212Fb72ae65367A7c887eC4Ad9bE310BAC611BF`
  — checked directly with `getCurrencies()`), but passing it as `feeCurrency` from inside MiniPay
  produces the exact same "insufficient funds, have 0 want <gas cost>" native-CELO error as leaving
  `feeCurrency` off entirely — MiniPay's own wallet only seems to implement fee abstraction for its
  documented "blessed" tokens (USDm/USDC/USDT), regardless of what the protocol-level allowlist says.
  Switching only the `feeCurrency` field to USDm (keeping the `approve()` call's token/amount as
  COPm) fixed it immediately, with no other change. **Consequence**: a passenger needs a small USDm
  balance in addition to their COPm, purely to cover the network fee — worth a low-balance explainer
  or a deposit-deeplink redirect for USDm specifically before this ships (see `minipay-requirements.md`
  → Currency & Stablecoin Logic).

Known gaps: no phone-number identity yet (shows a truncated `0x…` address, which MiniPay only
allows as a secondary hint, not primary — see `minipay-guide.md` → ODIS/FederatedAttestations for
the real fix); no low-balance redirect to MiniPay's Deposit deeplink yet; no stats/analytics page;
not yet deployed anywhere (no Celo Sepolia or Mainnet `VIA_Operator` address to point it at — that's
the next step).

### Networks

Celo migrated to an L2 (OP Stack) in March 2025. **Alfajores is deprecated** — confirmed live via
`docs.celo.org` and `faucet.celo.org` (which now only offers Celo Sepolia). Use Celo Sepolia as the
testnet step before mainnet.

| | Celo Sepolia (testnet) | Celo Mainnet |
|---|---|---|
| Chain ID | `11142220` | `42220` |
| RPC | `https://forno.celo-sepolia.celo-testnet.org` | `https://forno.celo.org` |
| Explorer | celo-sepolia.blockscout.com | celoscan.io |
| Faucet | faucet.celo.org, Google Cloud Web3 faucet | — |

Verified payment-token addresses (checked on-chain via Blockscout, not just docs — don't reuse an
address from a reference file without independently re-verifying, see next section):
- COPm, Celo mainnet: `0x8A567e2aE79CA692Bd748aB832081C45de4041eA`
- COPm, Celo Sepolia (the Mento v2 deployment — verified via a wallet's actual token holdings on
  Blockscout after a real swap, not a reference file): `0x5F8d55c3627d2dc0a2B4afa798f877242F382F67`
- USDm, Celo Sepolia (no longer the payment token, but still the required `feeCurrency` for the
  MiniPay top-up transaction — see Frontend Architecture above):
  `0xdE9e4C3ce781b4bA68120d6261cbad65ce0aB00b`
- FeeCurrencyDirectory, Celo Sepolia (queried directly with `getCurrencies()` to confirm which
  tokens are valid `feeCurrency` values at the protocol level — COPm is in this list, even though
  MiniPay's own wallet doesn't actually support it as one, see above):
  `0x9212Fb72ae65367A7c887eC4Ad9bE310BAC611BF`

### `.agents/skills/celopedia-skill` — Celo reference skill, verify before trusting

Installed via `npx skills add celo-org/celopedia-skills`, symlinked at `.claude/skills/celopedia-skill`.
Useful for Celo ecosystem questions (network info, contract addresses, fee-abstraction mechanics,
MiniPay/DeFi reference). **Its bundled `contracts.md` testnet address table has been caught stale at
least once** (a USDm address that didn't match the real on-chain token) — always independently verify
any address it gives you against Blockscout/Celoscan before using it in a deploy or config, exactly as
was done for the addresses listed above.

## Blockchain code conventions (from `celopedia.md`)

`celopedia.md` at the repo root is a Celo-specific rules file (originally written for Copilot, applies
here too):
- Always write blockchain code in **viem** + TypeScript. Never ethers.js or web3.js.
- For any React/Next.js frontend, use **Wagmi** hooks.
- Target wallet is **MiniPay**: user identity is a phone number, not a raw hex address.
- Banned jargon in user-facing strings: no "Gas" or "Tokens" — use "Network fee" and "Digital Pesos
  (cCOP)" / "Digital Dollars".
- Always pass viem's `feeCurrency` param with the real fee-currency contract address when sending a
  transaction (native fee abstraction).

## Git workflow

- Commits land in small, scoped batches (contracts, firmware, frontend, docs each committed
  separately) — this repo is tracked under Celo's "Proof of Ship" program, which rewards visible
  day-by-day progress, so don't bulk-stage the whole working tree in one commit.
- Commit messages do **not** include a `Co-Authored-By` trailer.
