// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "forge-std/Test.sol";
import "../src/VIAToken.sol";
import "../src/VIA_Operator.sol";

contract VIANetworkTest is Test {
    VIAToken public token;
    VIA_Operator public operator;

    // Usuarios de prueba
    address public admin = address(1);
    address public bus_validador = address(2);
    address public pasajero = address(3);

    function setUp() public {
        // Ejecutamos como admin
        vm.startPrank(admin);

        // 1. Desplegar contratos
        token = new VIAToken();
        operator = new VIA_Operator(address(token));

        // 2. Configurar Roles
        // El operador necesita permiso para quemar tokens
        token.grantRole(token.OPERATOR_ROLE(), address(operator));
        // El bus físico necesita permiso para cobrar
        operator.grantRole(operator.VALIDATOR_ROLE(), bus_validador);

        // 3. Simular recarga de saldo al pasajero
        // Le damos 10,000 VIA para sus viajes
        token.mint(pasajero, 10000);

        vm.stopPrank();
    }

    // TEST 1: Verificar que el pasajero recibió sus tokens
    function test_InitialBalance() public view {
        assertEq(token.balanceOf(pasajero), 10000);
    }

    // TEST 2: Cobro de pasaje exitoso (Urbano - Zona 1)
    function test_CollectFare_Success() public {
        uint256 balanceInicial = token.balanceOf(pasajero);
        uint256 precioZona1 = operator.zonePrices(1);

        // El bus cobra el pasaje
        vm.prank(bus_validador);
        operator.collectFare(pasajero, 101, 1); // User, BusID 101, Zone 1

        assertEq(token.balanceOf(pasajero), balanceInicial - precioZona1);
    }

    // TEST 3: Seguridad - Un usuario no puede cobrarse a sí mismo
    function test_Security_OnlyValidatorCanCollect() public {
        vm.prank(pasajero);
        // Debe fallar porque el pasajero no es un validador autorizado
        vm.expectRevert(); 
        operator.collectFare(pasajero, 101, 1);
    }

    // TEST 4: Seguridad - No se puede cobrar más de lo que el usuario tiene
    function test_InsufficientBalance() public {
        address pasajeroPobre = address(4);
        // No le hacemos mint de nada (balance 0)

        vm.prank(bus_validador);
        vm.expectRevert(); // El burn de OpenZeppelin fallará por saldo insuficiente
        operator.collectFare(pasajeroPobre, 101, 1);
    }

    // TEST 5: Cambio de tarifas por el Admin
    function test_Admin_UpdatePrice() public {
        vm.prank(admin);
        operator.setZonePrice(1, 2000);
        
        assertEq(operator.zonePrices(1), 2000);
    }

    function test_Gas_CollectFare() public {
    // El bus cobra el pasaje
    vm.prank(bus_validador);
    operator.collectFare(pasajero, 101, 1);
    }

    // TEST 6: Desactivar un bus y verificar que no pueda cobrar
    function test_DeactivateBus() public {
    // 1. Verificar que el bus puede cobrar inicialmente
    vm.prank(bus_validador);
    operator.collectFare(pasajero, 101, 1);

    // 2. El admin desactiva el bus
    vm.prank(admin);
    operator.deactivateBus(bus_validador);

    // 3. El bus intenta cobrar de nuevo y DEBE fallar
    vm.prank(bus_validador);
    vm.expectRevert(); 
    operator.collectFare(pasajero, 101, 1);
}
}