"use client";

import { useCallback, useEffect, useState } from "react";
import { encodeFunctionData, formatUnits } from "viem";
import { chain, operatorAddress, isConfigured, DEFAULT_ZONE_ID, DEPLOY_BLOCK } from "@/lib/config";
import { erc20Abi, operatorAbi } from "@/lib/abi";
import { getPublicClient, getWalletClient, isMiniPay } from "@/lib/minipay";

type Fare = {
  txHash: string;
  amount: bigint;
  busId: bigint;
  zoneId: bigint;
  timestamp: bigint;
};

type TokenInfo = {
  address: `0x${string}`;
  symbol: string;
  decimals: number;
};

// Recargas preconfiguradas, en numero de pasajes de la zona por defecto — la aprobacion queda
// acotada a un monto concreto en vez de un allowance ilimitado (ver CLAUDE.md, seccion de seguridad).
const TOP_UP_RIDES = [5, 10, 20];

export default function Home() {
  const [address, setAddress] = useState<`0x${string}` | null>(null);
  const [connecting, setConnecting] = useState(true);
  const [walletMissing, setWalletMissing] = useState(false);

  const [token, setToken] = useState<TokenInfo | null>(null);
  const [balance, setBalance] = useState<bigint | null>(null);
  const [allowance, setAllowance] = useState<bigint | null>(null);
  const [zonePrice, setZonePrice] = useState<bigint | null>(null);
  const [fares, setFares] = useState<Fare[]>([]);

  const [pendingRides, setPendingRides] = useState<number | null>(null);
  const [error, setError] = useState<string | null>(null);

  // --- Conexion: auto-connect dentro de MiniPay, boton explicito fuera de ella. ---
  const connect = useCallback(async () => {
    const wallet = getWalletClient();
    if (!wallet) {
      setWalletMissing(true);
      setConnecting(false);
      return;
    }
    try {
      const accounts = isMiniPay()
        ? await wallet.getAddresses()
        : await wallet.requestAddresses();
      if (accounts[0]) setAddress(accounts[0]);
    } catch {
      setError("No se pudo conectar la wallet.");
    } finally {
      setConnecting(false);
    }
  }, []);

  useEffect(() => {
    if (isMiniPay()) {
      // Auto-connect on mount; setState in connect() runs after an await, not synchronously here.
      // eslint-disable-next-line react-hooks/set-state-in-effect
      void connect();
    } else {
      setConnecting(false);
    }
  }, [connect]);

  // --- Datos on-chain: token de pago, saldo, aprobacion, precio de zona, historial. ---
  const refresh = useCallback(async () => {
    if (!address) return;
    const client = getPublicClient();

    const tokenAddress = await client.readContract({
      address: operatorAddress,
      abi: operatorAbi,
      functionName: "getPaymentToken",
    });

    const [symbol, decimals, bal, allow, price] = await Promise.all([
      client.readContract({ address: tokenAddress, abi: erc20Abi, functionName: "symbol" }),
      client.readContract({ address: tokenAddress, abi: erc20Abi, functionName: "decimals" }),
      client.readContract({ address: tokenAddress, abi: erc20Abi, functionName: "balanceOf", args: [address] }),
      client.readContract({
        address: tokenAddress,
        abi: erc20Abi,
        functionName: "allowance",
        args: [address, operatorAddress],
      }),
      client.readContract({
        address: operatorAddress,
        abi: operatorAbi,
        functionName: "getZonePrice",
        args: [DEFAULT_ZONE_ID],
      }),
    ]);

    setToken({ address: tokenAddress, symbol, decimals });
    setBalance(bal);
    setAllowance(allow);
    setZonePrice(price);

    const logs = await client.getLogs({
      address: operatorAddress,
      event: operatorAbi[2],
      args: { user: address },
      fromBlock: DEPLOY_BLOCK,
      toBlock: "latest",
    });

    setFares(
      logs
        .map((log) => ({
          txHash: log.transactionHash,
          amount: log.args.amount!,
          busId: log.args.busId!,
          zoneId: log.args.zoneId!,
          timestamp: log.args.timestamp!,
        }))
        .reverse(),
    );
  }, [address]);

  useEffect(() => {
    // Fetch on-chain data when the address changes; same async-after-await reasoning as above.
    // eslint-disable-next-line react-hooks/set-state-in-effect
    void refresh();
  }, [refresh]);

  // --- Recarga: aprueba exactamente el monto de N pasajes (no un allowance ilimitado). ---
  async function topUp(rides: number) {
    if (!address || !token || !zonePrice) return;
    const wallet = getWalletClient();
    if (!wallet) return;

    setPendingRides(rides);
    setError(null);
    try {
      const amount = zonePrice * BigInt(rides);
      const data = encodeFunctionData({
        abi: erc20Abi,
        functionName: "approve",
        args: [operatorAddress, amount],
      });

      // token.address == feeCurrency para tokens Mento de 18 decimales (COPm/USDm). USDC/USDT
      // necesitarian la direccion adaptadora en vez de la del token — ver builder-guide.md.
      await wallet.sendTransaction({
        account: address,
        to: token.address,
        data,
        feeCurrency: token.address,
      });

      await refresh();
    } catch {
      setError("La recarga no se pudo completar. Intenta de nuevo.");
    } finally {
      setPendingRides(null);
    }
  }

  const ridesRemaining =
    allowance !== null && zonePrice !== null && zonePrice > 0n ? allowance / zonePrice : null;

  if (!isConfigured()) {
    return (
      <div className="flex flex-1 items-center justify-center bg-zinc-50 p-6 dark:bg-black">
        <p className="max-w-sm text-center text-sm text-zinc-600 dark:text-zinc-400">
          Falta configuracion: copia <code>.env.local.example</code> a <code>.env.local</code> y
          completa <code>NEXT_PUBLIC_RPC_URL</code> y <code>NEXT_PUBLIC_OPERATOR_ADDRESS</code>.
        </p>
      </div>
    );
  }

  return (
    <div className="flex flex-col flex-1 items-center bg-zinc-50 font-sans dark:bg-black">
      <main className="flex flex-1 w-full max-w-sm flex-col gap-6 px-5 py-10">
        <header className="flex items-center gap-3">
          <div className="h-9 w-9 shrink-0 rounded-full bg-lime-400 dark:bg-lime-500" aria-hidden />
          <div>
            <h1 className="text-lg font-semibold text-zinc-900 dark:text-zinc-50">VIA Pay</h1>
            <p className="text-xs text-zinc-500 dark:text-zinc-400">
              {chain.name} · Pasaje de transporte publico
            </p>
          </div>
        </header>

        {connecting && <p className="text-sm text-zinc-500">Conectando…</p>}

        {walletMissing && !connecting && (
          <p className="rounded-lg bg-zinc-100 p-4 text-sm text-zinc-700 dark:bg-zinc-900 dark:text-zinc-300">
            Abre esta pagina dentro de MiniPay para continuar.
          </p>
        )}

        {!connecting && !address && !walletMissing && (
          <button
            onClick={connect}
            className="rounded-full bg-zinc-900 px-5 py-3 text-sm font-medium text-white dark:bg-zinc-50 dark:text-zinc-900"
          >
            Conectar
          </button>
        )}

        {address && (
          <>
            <section className="rounded-xl bg-white p-5 shadow-sm dark:bg-zinc-900">
              <p className="text-xs uppercase tracking-wide text-zinc-500 dark:text-zinc-400">Saldo</p>
              <p className="mt-1 text-3xl font-semibold tabular-nums text-zinc-900 dark:text-zinc-50">
                {balance !== null && token ? formatUnits(balance, token.decimals) : "—"}{" "}
                <span className="text-lg text-zinc-500 dark:text-zinc-400">{token?.symbol}</span>
              </p>
              <p className="mt-3 text-xs text-zinc-400">
                Cuenta: {address.slice(0, 6)}…{address.slice(-4)}
              </p>
            </section>

            <section className="rounded-xl bg-white p-5 shadow-sm dark:bg-zinc-900">
              <p className="text-xs uppercase tracking-wide text-zinc-500 dark:text-zinc-400">
                Pasajes aprobados
              </p>
              <p className="mt-1 text-2xl font-semibold tabular-nums text-zinc-900 dark:text-zinc-50">
                {ridesRemaining !== null ? ridesRemaining.toString() : "—"}
              </p>
              <div className="mt-4 flex gap-2">
                {TOP_UP_RIDES.map((rides) => (
                  <button
                    key={rides}
                    onClick={() => topUp(rides)}
                    disabled={pendingRides !== null}
                    className="flex-1 rounded-lg bg-lime-400 py-2 text-sm font-medium text-zinc-900 disabled:opacity-50 dark:bg-lime-500"
                  >
                    {pendingRides === rides ? "…" : `+${rides}`}
                  </button>
                ))}
              </div>
              {error && <p className="mt-2 text-xs text-red-600">{error}</p>}
            </section>

            <section className="rounded-xl bg-white p-5 shadow-sm dark:bg-zinc-900">
              <p className="text-xs uppercase tracking-wide text-zinc-500 dark:text-zinc-400">
                Viajes recientes
              </p>
              {fares.length === 0 && (
                <p className="mt-2 text-sm text-zinc-400">Aun no hay viajes registrados.</p>
              )}
              <ul className="mt-2 divide-y divide-zinc-100 dark:divide-zinc-800">
                {fares.slice(0, 10).map((fare) => (
                  <li key={fare.txHash} className="flex items-center justify-between py-2 text-sm">
                    <span className="text-zinc-600 dark:text-zinc-300">
                      Bus {fare.busId.toString()} · Zona {fare.zoneId.toString()}
                    </span>
                    <span className="tabular-nums text-zinc-900 dark:text-zinc-50">
                      -{token ? formatUnits(fare.amount, token.decimals) : fare.amount.toString()}
                    </span>
                  </li>
                ))}
              </ul>
            </section>
          </>
        )}

        <footer className="mt-auto pt-6 text-center text-xs text-zinc-400">
          Via Network · Operado por Via Network SAS
          {/* TODO: enlaces reales de soporte y Terminos/Privacidad antes de enviar a revision de MiniPay */}
        </footer>
      </main>
    </div>
  );
}
