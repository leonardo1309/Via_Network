import Link from "next/link";

export const metadata = {
  title: "Terminos de Servicio - VIA Pay",
};

export default function TermsOfService() {
  return (
    <div className="mx-auto flex w-full max-w-sm flex-1 flex-col gap-4 px-5 py-10 text-sm text-zinc-700 dark:text-zinc-300">
      <Link href="/" className="text-xs text-zinc-400 hover:underline">
        &larr; Volver
      </Link>
      <h1 className="text-lg font-semibold text-zinc-900 dark:text-zinc-50">
        Terminos de Servicio
      </h1>
      <p className="text-xs text-zinc-400">Ultima actualizacion: borrador inicial, pendiente de revision legal.</p>

      <p>
        VIA Pay es operada por Via Network SAS (&quot;Via Network&quot;, &quot;nosotros&quot;). Al usar esta MiniApp
        dentro de MiniPay aceptas estos terminos.
      </p>

      <h2 className="font-semibold text-zinc-900 dark:text-zinc-50">1. Que hace VIA Pay</h2>
      <p>
        VIA Pay te permite aprobar el uso de tu saldo en stablecoin (COPm) para que un validador
        fisico instalado en un bus autorizado cobre el valor de tu pasaje directamente desde tu
        billetera hacia la cuenta de la empresa de transporte, a traves del contrato inteligente
        `VIA_Operator` en la red Celo.
      </p>

      <h2 className="font-semibold text-zinc-900 dark:text-zinc-50">2. Tu responsabilidad</h2>
      <p>
        Tu eres responsable de mantener saldo suficiente y de la custodia de tu billetera. Via
        Network nunca custodia tus fondos: el contrato transfiere directamente de tu billetera a
        la tesoreria de la empresa de transporte en cada cobro autorizado.
      </p>

      <h2 className="font-semibold text-zinc-900 dark:text-zinc-50">3. Aprobaciones acotadas</h2>
      <p>
        Cada recarga aprueba un monto especifico (el valor de N pasajes), nunca un monto
        ilimitado. Puedes revisar y revocar la aprobacion en cualquier momento desde tu
        billetera.
      </p>

      <h2 className="font-semibold text-zinc-900 dark:text-zinc-50">4. Sin garantias</h2>
      <p>
        El servicio se ofrece &quot;tal cual&quot;, en fase de pruebas sobre Celo Sepolia y en desarrollo
        activo. Puede haber interrupciones o cambios sin previo aviso mientras el proyecto
        madura.
      </p>

      <h2 className="font-semibold text-zinc-900 dark:text-zinc-50">5. Contacto</h2>
      <p>
        Preguntas o incidencias: contactanos por el enlace de soporte en la pantalla principal.
      </p>
    </div>
  );
}
