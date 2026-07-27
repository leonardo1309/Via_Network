export const operatorAbi = [
  {
    type: "function",
    name: "collectFareWithSig",
    stateMutability: "nonpayable",
    inputs: [
      { name: "_user", type: "address" },
      { name: "_busId", type: "uint256" },
      { name: "_zoneId", type: "uint256" },
      { name: "_nonce", type: "uint256" },
      { name: "_signature", type: "bytes" },
    ],
    outputs: [],
  },
  {
    type: "function",
    name: "getNonce",
    stateMutability: "view",
    inputs: [{ name: "_validator", type: "address" }],
    outputs: [{ name: "", type: "uint256" }],
  },
] as const;
