// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {Script, console} from "forge-std/Script.sol";
import {VIA_Operator} from "../src/VIA_Operator.sol";
import {HelperConfig} from "./HelperConfig.s.sol";

contract DeployVIA is Script {
    function run() external returns (VIA_Operator, HelperConfig) {
        HelperConfig helperConfig = new HelperConfig();
        (address paymentToken, address treasury) = helperConfig.activeNetworkConfig();

        // Anvil local: firma con PRIVATE_KEY (una cuenta de prueba publica de Anvil, sin fondos
        // reales en riesgo). Celo Sepolia/Mainnet: sin argumentos — firma con un keystore cifrado
        // via `--account <nombre> --sender <direccion>` (ver README), para no exponer una llave
        // real en texto plano en .env.
        if (block.chainid == helperConfig.LOCAL_CHAIN_ID()) {
            vm.startBroadcast(vm.envUint("PRIVATE_KEY"));
        } else {
            vm.startBroadcast();
        }
        VIA_Operator operator = new VIA_Operator(paymentToken, treasury);
        vm.stopBroadcast();

        console.log("VIA Operator deployed at:", address(operator));
        console.log("Payment token:", paymentToken);
        console.log("Treasury:", treasury);

        return (operator, helperConfig);
    }
}
