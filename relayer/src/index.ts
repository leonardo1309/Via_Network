import "dotenv/config";
import express from "express";
import { encodeFunctionData, isAddress, isHex } from "viem";
import { account, feeCurrencyAddress, operatorAddress, publicClient, walletClient } from "./chain.js";
import { operatorAbi } from "./abi.js";

const app = express();
app.use(express.json());

// El validador (ESP32) consulta este nonce antes de firmar el siguiente cobro.
app.get("/nonce/:validator", async (req, res) => {
  const { validator } = req.params;
  if (!isAddress(validator)) {
    return res.status(400).json({ error: "direccion de validador invalida" });
  }

  const nonce = await publicClient.readContract({
    address: operatorAddress,
    abi: operatorAbi,
    functionName: "getNonce",
    args: [validator],
  });

  res.json({ nonce: nonce.toString() });
});

// Recibe la intención de cobro firmada (EIP-712) por el validador y la retransmite
// on-chain pagando el gas en feeCurrency (USDm) en vez de CELO nativo.
app.post("/collect-fare", async (req, res) => {
  const { user, busId, zoneId, nonce, signature } = req.body ?? {};

  if (
    !isAddress(user) ||
    !isHex(signature) ||
    !Number.isInteger(busId) ||
    !Number.isInteger(zoneId) ||
    !Number.isInteger(nonce)
  ) {
    return res.status(400).json({ error: "payload invalido" });
  }

  try {
    const data = encodeFunctionData({
      abi: operatorAbi,
      functionName: "collectFareWithSig",
      args: [user, BigInt(busId), BigInt(zoneId), BigInt(nonce), signature],
    });

    const hash = await walletClient.sendTransaction({
      to: operatorAddress,
      data,
      feeCurrency: feeCurrencyAddress,
    });

    res.json({ txHash: hash });
  } catch (err) {
    console.error("[relayer] fallo al retransmitir la transaccion:", err);
    res.status(502).json({ error: (err as Error).message });
  }
});

const port = Number(process.env.PORT ?? 3001);
app.listen(port, () => {
  console.log(`Relayer VIA Network escuchando en :${port}`);
  console.log(`Cuenta relayer (paga gas en ${feeCurrencyAddress}): ${account.address}`);
  console.log(`VIA_Operator: ${operatorAddress}`);
});
