// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {Script} from "forge-std/Script.sol";
import {MockPaymentToken} from "../test/mocks/MockPaymentToken.sol";

/**
 * @title HelperConfig
 * @author Via Network
 * @notice Resuelve la configuracion de red (token de pago y tesoreria) segun el chain activo,
 * para que `Deploy.s.sol` no tenga direcciones hardcodeadas ni dependa de variables de entorno
 * que no aplican a la red actual.
 * @dev En Anvil local despliega un `MockPaymentToken` automaticamente. En Celo Sepolia/Mainnet
 * usa las direcciones de stablecoin verificadas on-chain (ver CLAUDE.md) y una tesoreria provista
 * por variable de entorno, ya que esa si es informacion real del negocio, no una constante de chain.
 */
contract HelperConfig is Script {
    /*//////////////////////////////////////////////////////////////////////
                               TYPE DECLARATIONS
    //////////////////////////////////////////////////////////////////////*/
    struct NetworkConfig {
        address paymentToken;
        address treasury;
    }

    /*//////////////////////////////////////////////////////////////////////
                               STATE VARIABLES
    //////////////////////////////////////////////////////////////////////*/
    uint256 public constant CELO_MAINNET_CHAIN_ID = 42220;
    uint256 public constant CELO_SEPOLIA_CHAIN_ID = 11142220;
    uint256 public constant LOCAL_CHAIN_ID = 31337;

    /// @dev Cuenta #1 por defecto de Anvil — solo como tesoreria de prueba en local.
    address public constant ANVIL_DEFAULT_TREASURY = 0x70997970c51812dc3a010c7D01B50E0D17Dc79c9;

    NetworkConfig public activeNetworkConfig;

    /*//////////////////////////////////////////////////////////////////////
                                  FUNCTIONS
    //////////////////////////////////////////////////////////////////////*/
    constructor() {
        if (block.chainid == CELO_MAINNET_CHAIN_ID) {
            activeNetworkConfig = getCeloMainnetConfig();
        } else if (block.chainid == CELO_SEPOLIA_CHAIN_ID) {
            activeNetworkConfig = getCeloSepoliaConfig();
        } else {
            activeNetworkConfig = getOrCreateAnvilConfig();
        }
    }

    /// @notice Configuracion para Celo Mainnet: COPm real + tesoreria de la empresa de transporte.
    function getCeloMainnetConfig() public view returns (NetworkConfig memory) {
        return NetworkConfig({
            paymentToken: 0x8A567e2aE79CA692Bd748aB832081C45de4041eA, // COPm, verificado en Celoscan
            treasury: vm.envAddress("TREASURY_ADDRESS")
        });
    }

    /// @notice Configuracion para Celo Sepolia: USDm como stand-in (COPm no tiene despliegue v3 ahi).
    function getCeloSepoliaConfig() public view returns (NetworkConfig memory) {
        return NetworkConfig({
            paymentToken: 0xdE9e4C3ce781b4bA68120d6261cbad65ce0aB00b, // USDm, verificado en Blockscout
            treasury: vm.envAddress("TREASURY_ADDRESS")
        });
    }

    /// @notice Configuracion para Anvil local: despliega un token mock si aun no existe uno.
    function getOrCreateAnvilConfig() public returns (NetworkConfig memory) {
        if (activeNetworkConfig.paymentToken != address(0)) {
            return activeNetworkConfig;
        }

        vm.startBroadcast();
        MockPaymentToken mockToken = new MockPaymentToken();
        vm.stopBroadcast();

        return NetworkConfig({paymentToken: address(mockToken), treasury: ANVIL_DEFAULT_TREASURY});
    }
}
