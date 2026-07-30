"use client";

import { useCallback, useEffect, useState } from "react";
import Image from "next/image";
import Link from "next/link";
import { encodeFunctionData, formatUnits } from "viem";
import {
  useAccount,
  useConnect,
  useReadContract,
  useReadContracts,
  usePublicClient,
} from "wagmi";
import {
  chain,
  operatorAddress,
  isConfigured,
  DEFAULT_ZONE_ID,
  DEPLOY_BLOCK,
  MINIPAY_FEE_CURRENCY,
} from "@/lib/config";
import { erc20Abi, operatorAbi } from "@/lib/abi";
import { isMiniPay, hasInjectedProvider, getWalletClient } from "@/lib/minipay";

type Fare = {
  txHash: string;
  amount: bigint;
  busId: bigint;
  zoneId: bigint;
  timestamp: bigint;
};

// Recargas preconfiguradas, en numero de pasajes de la zona por defecto — la aprobacion queda
// acotada a un monto concreto en vez de un allowance ilimitado (ver CLAUDE.md, seccion de seguridad).
const TOP_UP_RIDES = [5, 10, 20];

export default function Home() {
  const { address, isConnected } = useAccount();
  const { connect, connectors, isPending: connectPending } = useConnect();
  const publicClient = usePublicClient();

  const [checkedWallet, setCheckedWallet] = useState(false);
  const [walletMissing, setWalletMissing] = useState(false);
  const [providerCheckAttempts, setProviderCheckAttempts] = useState(0);
  const [fares, setFares] = useState<Fare[]>([]);
  const [addressCopied, setAddressCopied] = useState(false);
  const [pendingRides, setPendingRides] = useState<number | null>(null);
  const [error, setError] = useState<string | null>(null);

  // --- Conexion: auto-connect dentro de MiniPay, boton explicito fuera de ella (zero-click connect). ---
  // Algunos wallets (MiniPay incluido) inyectan window.ethereum despues del primer render, no antes —
  // reintenta por ~4s en vez de decidir "sin wallet" en la primera revision.
  useEffect(() => {
    const MAX_ATTEMPTS = 20;
    if (hasInjectedProvider()) {
      if (isMiniPay()) {
        connect({ connector: connectors[0] });
      }
      // eslint-disable-next-line react-hooks/set-state-in-effect
      setCheckedWallet(true);
      return;
    }
    if (providerCheckAttempts >= MAX_ATTEMPTS) {
      setWalletMissing(true);
      setCheckedWallet(true);
      return;
    }
    const timer = setTimeout(() => setProviderCheckAttempts((n) => n + 1), 200);
    return () => clearTimeout(timer);
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [providerCheckAttempts]);

  // --- Datos on-chain: token de pago, saldo, aprobacion, precio de zona (via wagmi). ---
  const { data: tokenAddress } = useReadContract({
    address: operatorAddress,
    abi: operatorAbi,
    functionName: "getPaymentToken",
  });

  const { data: tokenData, refetch: refetchTokenData } = useReadContracts({
    allowFailure: false,
    contracts:
      address && tokenAddress
        ? ([
            { address: tokenAddress, abi: erc20Abi, functionName: "symbol" },
            { address: tokenAddress, abi: erc20Abi, functionName: "decimals" },
            { address: tokenAddress, abi: erc20Abi, functionName: "balanceOf", args: [address] },
            {
              address: tokenAddress,
              abi: erc20Abi,
              functionName: "allowance",
              args: [address, operatorAddress],
            },
            {
              address: operatorAddress,
              abi: operatorAbi,
              functionName: "getZonePrice",
              args: [DEFAULT_ZONE_ID],
            },
          ] as const)
        : [],
    // Un validador puede cobrar un pasaje en cualquier momento fuera de la app (tap en el bus) —
    // sin polling, el saldo/allowance quedarian obsoletos hasta que el usuario cierre y reabra.
    query: { enabled: Boolean(address && tokenAddress), refetchInterval: 3000 },
  });

  const [symbol, decimals, balance, allowance, zonePrice] = tokenData ?? [];

  // --- Historial: eventos FarePaid del pasajero conectado. ---
  const refreshFares = useCallback(async () => {
    if (!address || !publicClient) return;
    const logs = await publicClient.getLogs({
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
  }, [address, publicClient]);

  useEffect(() => {
    // Fetch on-chain data when the address changes; setFares runs after an await, not synchronously here.
    // eslint-disable-next-line react-hooks/set-state-in-effect
    void refreshFares();

    // Igual que el saldo/allowance arriba: un cobro fuera de la app no dispara ningun re-render por
    // si solo, asi que hay que re-consultar los logs periodicamente para que el historial se actualice
    // sin que el usuario tenga que cerrar y volver a abrir la MiniApp.
    const interval = setInterval(() => void refreshFares(), 3000);
    return () => clearInterval(interval);
  }, [refreshFares]);

  // --- Recarga: aprueba exactamente el monto de N pasajes (no un allowance ilimitado). ---
  async function topUp(rides: number) {
    if (!address || !tokenAddress || zonePrice === undefined) return;
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

      // La red fee siempre se paga en USDm, no en el token de pasajes (COPm) — ver MINIPAY_FEE_CURRENCY.
      await wallet.sendTransaction({
        account: address,
        to: tokenAddress,
        data,
        feeCurrency: MINIPAY_FEE_CURRENCY,
      });

      await Promise.all([refetchTokenData(), refreshFares()]);
    } catch {
      setError("La recarga no se pudo completar. Verifica que tengas saldo de USDm para la red fee.");
    } finally {
      setPendingRides(null);
    }
  }

  const ridesRemaining =
    allowance !== undefined && zonePrice !== undefined && zonePrice > 0n
      ? allowance / zonePrice
      : null;

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

  const initializing = !checkedWallet || connectPending;

  return (
    <div className="flex flex-col flex-1 items-center bg-zinc-50 font-sans dark:bg-black">
      <main className="flex flex-1 w-full max-w-sm flex-col gap-6 px-5 py-10">
        <header className="flex items-center gap-3">
          <Image
            src="/logo.png"
            alt="Via Network"
            width={36}
            height={36}
            className="h-9 w-9 shrink-0 rounded-full"
            priority
          />
          <div>
            <h1 className="text-lg font-semibold text-zinc-900 dark:text-zinc-50">VIA Pay</h1>
            <p className="text-xs text-zinc-500 dark:text-zinc-400">
              {chain.name} · Pasaje de transporte publico
            </p>
          </div>
        </header>

        {initializing && <p className="text-sm text-zinc-500">Conectando…</p>}

        {!initializing && walletMissing && (
          <p className="rounded-lg bg-zinc-100 p-4 text-sm text-zinc-700 dark:bg-zinc-900 dark:text-zinc-300">
            Abre esta pagina dentro de MiniPay para continuar.
          </p>
        )}

        {/* Boton manual solo fuera de MiniPay — nunca mostrar "Conectar" dentro de MiniPay (zero-click connect). */}
        {!initializing && !walletMissing && !isConnected && !isMiniPay() && (
          <button
            onClick={() => connect({ connector: connectors[0] })}
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
                {balance !== undefined && decimals !== undefined ? formatUnits(balance, decimals) : "—"}{" "}
                <span className="text-lg text-zinc-500 dark:text-zinc-400">{symbol}</span>
              </p>
              <button
                onClick={() => {
                  navigator.clipboard.writeText(address).then(() => {
                    setAddressCopied(true);
                    setTimeout(() => setAddressCopied(false), 2000);
                  });
                }}
                className="mt-3 text-xs text-zinc-400 underline decoration-dotted underline-offset-2"
              >
                {addressCopied
                  ? "Direccion copiada"
                  : `Cuenta: ${address.slice(0, 6)}…${address.slice(-4)} (toca para copiar)`}
              </button>
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
                      -{decimals !== undefined ? formatUnits(fare.amount, decimals) : fare.amount.toString()}
                    </span>
                  </li>
                ))}
              </ul>
            </section>
          </>
        )}

        <footer className="mt-auto flex flex-col items-center gap-2 pt-6 text-center text-xs text-zinc-400">
          <p>Via Network · Operado por Via Network SAS</p>
          <nav className="flex gap-3 underline-offset-2">
            <a href="https://t.me/Le0_130" target="_blank" rel="noopener noreferrer" className="hover:underline">
              Soporte
            </a>
            <Link href="/tos" className="hover:underline">
              Terminos
            </Link>
            <Link href="/privacy" className="hover:underline">
              Privacidad
            </Link>
          </nav>
        </footer>
      </main>
    </div>
  );
}
