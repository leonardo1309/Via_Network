// Fragmento minimo de ERC20 — suficiente para balance, decimales y aprobacion.
export const erc20Abi = [
  {
    type: "function",
    name: "balanceOf",
    stateMutability: "view",
    inputs: [{ name: "account", type: "address" }],
    outputs: [{ name: "", type: "uint256" }],
  },
  {
    type: "function",
    name: "allowance",
    stateMutability: "view",
    inputs: [
      { name: "owner", type: "address" },
      { name: "spender", type: "address" },
    ],
    outputs: [{ name: "", type: "uint256" }],
  },
  {
    type: "function",
    name: "approve",
    stateMutability: "nonpayable",
    inputs: [
      { name: "spender", type: "address" },
      { name: "value", type: "uint256" },
    ],
    outputs: [{ name: "", type: "bool" }],
  },
  {
    type: "function",
    name: "decimals",
    stateMutability: "view",
    inputs: [],
    outputs: [{ name: "", type: "uint8" }],
  },
  {
    type: "function",
    name: "symbol",
    stateMutability: "view",
    inputs: [],
    outputs: [{ name: "", type: "string" }],
  },
] as const;

// Fragmento de VIA_Operator relevante para el pasajero (no incluye collectFare/collectFareWithSig,
// esas las firma el validador — ver firmware/ y relayer/).
export const operatorAbi = [
  {
    type: "function",
    name: "getPaymentToken",
    stateMutability: "view",
    inputs: [],
    outputs: [{ name: "", type: "address" }],
  },
  {
    type: "function",
    name: "getZonePrice",
    stateMutability: "view",
    inputs: [{ name: "_zoneId", type: "uint256" }],
    outputs: [{ name: "", type: "uint256" }],
  },
  {
    type: "event",
    name: "FarePaid",
    inputs: [
      { name: "user", type: "address", indexed: true },
      { name: "amount", type: "uint256", indexed: false },
      { name: "busId", type: "uint256", indexed: true },
      { name: "zoneId", type: "uint256", indexed: true },
      { name: "timestamp", type: "uint256", indexed: false },
    ],
  },
] as const;
