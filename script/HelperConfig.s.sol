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
    /// @dev paymentToken: stablecoin usado para pagar pasajes. treasury: wallet que los recibe.
    struct NetworkConfig {
        address paymentToken;
        address treasury;
    }

    /*//////////////////////////////////////////////////////////////////////
                               STATE VARIABLES
    //////////////////////////////////////////////////////////////////////*/
    uint256 public constant CELO_MAINNET_CHAIN_ID = 42220;
    uint256 public constant CELO_SEPOLIA_CHAIN_ID = 11142220;
    /// @dev Chain ID por defecto de Anvil. No se compara explicitamente contra este valor: cualquier
    /// chain que no sea Celo Mainnet/Sepolia cae en `getOrCreateAnvilConfig()` (ver constructor).
    uint256 public constant LOCAL_CHAIN_ID = 31337;

    /// @dev Cuenta #1 por defecto de Anvil — solo como tesoreria de prueba en local.
    address public constant ANVIL_DEFAULT_TREASURY = 0x70997970C51812dc3A010C7d01b50e0d17dc79C8;

    /// @notice Configuracion resuelta para el chain activo (`block.chainid` al momento del deploy).
    NetworkConfig public activeNetworkConfig;

    /*//////////////////////////////////////////////////////////////////////
                                  FUNCTIONS
    //////////////////////////////////////////////////////////////////////*/

    /// @notice Resuelve y cachea `activeNetworkConfig` segun `block.chainid` al desplegar este contrato.
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
    /// @return Config con el COPm verificado en Celoscan y `TREASURY_ADDRESS` desde variable de entorno.
    function getCeloMainnetConfig() public view returns (NetworkConfig memory) {
        return NetworkConfig({
            paymentToken: 0x8A567e2aE79CA692Bd748aB832081C45de4041eA, // COPm, verificado en Celoscan
            treasury: vm.envAddress("TREASURY_ADDRESS")
        });
    }

    /// @notice Configuracion para Celo Sepolia: COPm real (disponible via Mento V2, aunque V3 aun no
    /// tiene liquidez ahi — ver CLAUDE.md).
    /// @return Config con el COPm verificado en Blockscout y `TREASURY_ADDRESS` desde variable de entorno.
    function getCeloSepoliaConfig() public view returns (NetworkConfig memory) {
        return NetworkConfig({
            paymentToken: 0x5F8d55c3627d2dc0a2B4afa798f877242F382F67, // COPm, verificado en Blockscout
            treasury: vm.envAddress("TREASURY_ADDRESS")
        });
    }

    /// @notice Configuracion para Anvil local: despliega un token mock si aun no existe uno.
    /// @dev Cachea en `activeNetworkConfig` para no volver a desplegar el mock si esta funcion se
    /// llama mas de una vez dentro de la misma ejecucion del script.
    /// @return Config con el `MockPaymentToken` recien desplegado (o el ya existente) y la tesoreria
    /// de prueba fija `ANVIL_DEFAULT_TREASURY`.
    function getOrCreateAnvilConfig() public returns (NetworkConfig memory) {
        if (activeNetworkConfig.paymentToken != address(0)) {
            return activeNetworkConfig;
        }

        // Usa la misma llave que Deploy.s.sol (ya es un env var obligatorio para todo el script)
        // en vez del sender por defecto de Foundry, que `forge script --broadcast` rechaza sin
        // `--sender` explicito.
        vm.startBroadcast(vm.envUint("PRIVATE_KEY"));
        MockPaymentToken mockToken = new MockPaymentToken();
        vm.stopBroadcast();

        return NetworkConfig({paymentToken: address(mockToken), treasury: ANVIL_DEFAULT_TREASURY});
    }
}
