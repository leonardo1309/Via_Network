// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {Script, console} from "forge-std/Script.sol";
import {VIA_Operator} from "../src/VIA_Operator.sol";
import {HelperConfig} from "./HelperConfig.s.sol";

contract DeployVIA is Script {
    function run() external returns (VIA_Operator, HelperConfig) {
        HelperConfig helperConfig = new HelperConfig();
        (address paymentToken, address treasury) = helperConfig.activeNetworkConfig();

        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");
        vm.startBroadcast(deployerPrivateKey);
        VIA_Operator operator = new VIA_Operator(paymentToken, treasury);
        vm.stopBroadcast();

        console.log("VIA Operator deployed at:", address(operator));
        console.log("Payment token:", paymentToken);
        console.log("Treasury:", treasury);

        return (operator, helperConfig);
    }
}
