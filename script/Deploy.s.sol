// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {Script, console} from "forge-std/Script.sol";
import {VIAToken} from "../src/VIAToken.sol";
import {VIA_Operator} from "../src/VIA_Operator.sol";

contract DeployVIA is Script {
    function run() external {
        uint256 deployerPrivateKey = 0xac0974bec39a17e36ba4a6b4d238ff944bacb478cbed5efcae784d7bf4f2ff80;
        vm.startBroadcast(deployerPrivateKey);

        // 1. Desplegar Token
        VIAToken token = new VIAToken();
        
        // 2. Desplegar Operador pasándole la dirección del token
        VIA_Operator operator = new VIA_Operator(address(token));

        // 3. Configurar permisos: El operador DEBE poder quemar tokens
        token.grantRole(token.OPERATOR_ROLE(), address(operator));

        console.log("VIA Token deployed at:", address(token));
        console.log("VIA Operator deployed at:", address(operator));

        vm.stopBroadcast();
    }
}