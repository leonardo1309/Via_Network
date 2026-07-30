import Link from "next/link";

export const metadata = {
  title: "Politica de Privacidad - VIA Pay",
};

export default function PrivacyPolicy() {
  return (
    <div className="mx-auto flex w-full max-w-sm flex-1 flex-col gap-4 px-5 py-10 text-sm text-zinc-700 dark:text-zinc-300">
      <Link href="/" className="text-xs text-zinc-400 hover:underline">
        &larr; Volver
      </Link>
      <h1 className="text-lg font-semibold text-zinc-900 dark:text-zinc-50">
        Politica de Privacidad
      </h1>
      <p className="text-xs text-zinc-400">Ultima actualizacion: borrador inicial, pendiente de revision legal.</p>

      <p>
        Via Network SAS (&quot;Via Network&quot;, &quot;nosotros&quot;) opera VIA Pay, una MiniApp para MiniPay.
        Esta pagina explica que datos vemos y como los tratamos.
      </p>

      <h2 className="font-semibold text-zinc-900 dark:text-zinc-50">1. Que datos vemos</h2>
      <p>
        VIA Pay lee directamente de la blockchain Celo: tu direccion de billetera, tu saldo del
        token de pago, tu aprobacion vigente hacia `VIA_Operator`, y tu historial de cobros
        (`FarePaid`). Esta informacion ya es publica en la red Celo; VIA Pay no la almacena en
        servidores propios, solo la consulta en tiempo real para mostrartela.
      </p>

      <h2 className="font-semibold text-zinc-900 dark:text-zinc-50">2. Que no hacemos</h2>
      <p>
        No pedimos ni almacenamos tu clave privada. No accedemos a tu billetera fuera de las
        acciones que confirmas explicitamente dentro de MiniPay (aprobar un monto de recarga).
      </p>

      <h2 className="font-semibold text-zinc-900 dark:text-zinc-50">3. Terceros</h2>
      <p>
        VIA Pay se conecta al RPC publico de Celo/Celo Sepolia para leer y enviar transacciones.
        No compartimos datos con terceros mas alla de lo que ya es publico en la blockchain.
      </p>

      <h2 className="font-semibold text-zinc-900 dark:text-zinc-50">4. Contacto</h2>
      <p>
        Preguntas sobre privacidad: contactanos por el enlace de soporte en la pantalla
        principal.
      </p>
    </div>
  );
}
