// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "forge-std/Test.sol";
import {VIA_Operator} from "../src/VIA_Operator.sol";
import {MockPaymentToken} from "./mocks/MockPaymentToken.sol";

contract VIANetworkTest is Test {
    MockPaymentToken public paymentToken;
    VIA_Operator public operator;

    // Usuarios de prueba
    address public admin = address(1);
    address public busValidador = address(2);
    address public pasajero = address(3);
    address public treasury = address(4);

    // Validador con llave privada conocida, para poder firmar EIP-712 en los tests
    uint256 public constant VALIDADOR_RELAYER_PK = 0xA11CE;
    address public validadorRelayer;

    bytes32 public constant COLLECT_FARE_TYPEHASH =
        keccak256("CollectFare(address user,uint256 busId,uint256 zoneId,uint256 nonce)");

    function setUp() public {
        validadorRelayer = vm.addr(VALIDADOR_RELAYER_PK);

        // Ejecutamos como admin
        vm.startPrank(admin);

        // 1. Desplegar el token de pago (mock) y el operador
        paymentToken = new MockPaymentToken();
        operator = new VIA_Operator(address(paymentToken), treasury);

        // 2. Configurar roles: el bus físico y el validador-relayer pueden cobrar
        operator.grantRole(operator.VALIDATOR_ROLE(), busValidador);
        operator.grantRole(operator.VALIDATOR_ROLE(), validadorRelayer);

        vm.stopPrank();

        // 3. Simular recarga de saldo al pasajero y su aprobación al operador
        // (equivalente a que el pasajero ya haya cargado COPm y aprobado el contrato)
        paymentToken.mint(pasajero, 10000);
        vm.prank(pasajero);
        paymentToken.approve(address(operator), type(uint256).max);
    }

    function _signCollectFare(uint256 privateKey, address user, uint256 busId, uint256 zoneId, uint256 nonce)
        internal
        view
        returns (bytes memory)
    {
        bytes32 structHash = keccak256(abi.encode(COLLECT_FARE_TYPEHASH, user, busId, zoneId, nonce));

        bytes32 domainSeparator = keccak256(
            abi.encode(
                keccak256("EIP712Domain(string name,string version,uint256 chainId,address verifyingContract)"),
                keccak256(bytes("VIA_Operator")),
                keccak256(bytes("1")),
                block.chainid,
                address(operator)
            )
        );

        bytes32 digest = keccak256(abi.encodePacked("\x19\x01", domainSeparator, structHash));
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(privateKey, digest);
        return abi.encodePacked(r, s, v);
    }

    // TEST 1: Verificar que el pasajero recibió sus tokens
    function test_InitialBalance() public view {
        assertEq(paymentToken.balanceOf(pasajero), 10000);
    }

    // TEST 2: Cobro de pasaje exitoso (Urbano - Zona 1) — el saldo pasa del pasajero a la tesorería
    function test_CollectFare_Success() public {
        uint256 balanceInicialPasajero = paymentToken.balanceOf(pasajero);
        uint256 balanceInicialTesoreria = paymentToken.balanceOf(treasury);
        uint256 precioZona1 = operator.getZonePrice(1);

        // El bus cobra el pasaje
        vm.prank(busValidador);
        operator.collectFare(pasajero, 101, 1); // User, BusID 101, Zone 1

        assertEq(paymentToken.balanceOf(pasajero), balanceInicialPasajero - precioZona1);
        assertEq(paymentToken.balanceOf(treasury), balanceInicialTesoreria + precioZona1);
    }

    // TEST 3: Seguridad - Un usuario no puede cobrarse a sí mismo
    function test_Security_OnlyValidatorCanCollect() public {
        vm.prank(pasajero);
        // Debe fallar porque el pasajero no es un validador autorizado
        vm.expectRevert();
        operator.collectFare(pasajero, 101, 1);
    }

    // TEST 4: Seguridad - No se puede cobrar más de lo que el usuario tiene aprobado/en balance
    function test_InsufficientBalance() public {
        address pasajeroPobre = address(5);
        // No le hacemos mint ni approve: sin balance y sin allowance

        vm.prank(busValidador);
        vm.expectRevert(); // El transferFrom de OpenZeppelin fallará por saldo/allowance insuficiente
        operator.collectFare(pasajeroPobre, 101, 1);
    }

    // TEST 5: Cambio de tarifas por el Admin
    function test_Admin_UpdatePrice() public {
        vm.prank(admin);
        operator.setZonePrice(1, 2000);

        assertEq(operator.getZonePrice(1), 2000);
    }

    function test_Gas_CollectFare() public {
        // El bus cobra el pasaje
        vm.prank(busValidador);
        operator.collectFare(pasajero, 101, 1);
    }

    // TEST: Relayer retransmite un cobro firmado (EIP-712) por el validador
    function test_CollectFareWithSig_Success() public {
        uint256 balanceInicialPasajero = paymentToken.balanceOf(pasajero);
        uint256 balanceInicialTesoreria = paymentToken.balanceOf(treasury);
        uint256 precioZona1 = operator.getZonePrice(1);
        uint256 nonce = operator.getNonce(validadorRelayer);

        bytes memory signature = _signCollectFare(VALIDADOR_RELAYER_PK, pasajero, 101, 1, nonce);

        // Cualquiera (un relayer sin VALIDATOR_ROLE) puede enviar la transacción;
        // la autorización viene de la firma, no de quien paga el gas.
        address relayer = address(99);
        vm.prank(relayer);
        operator.collectFareWithSig(pasajero, 101, 1, nonce, signature);

        assertEq(paymentToken.balanceOf(pasajero), balanceInicialPasajero - precioZona1);
        assertEq(paymentToken.balanceOf(treasury), balanceInicialTesoreria + precioZona1);
        assertEq(operator.getNonce(validadorRelayer), nonce + 1);
    }

    // TEST: Un relayer no puede reutilizar (replay) la misma firma dos veces
    function test_CollectFareWithSig_RechazaReplay() public {
        uint256 nonce = operator.getNonce(validadorRelayer);
        bytes memory signature = _signCollectFare(VALIDADOR_RELAYER_PK, pasajero, 101, 1, nonce);

        operator.collectFareWithSig(pasajero, 101, 1, nonce, signature);

        vm.expectRevert();
        operator.collectFareWithSig(pasajero, 101, 1, nonce, signature);
    }

    // TEST: Una firma de una cuenta sin VALIDATOR_ROLE debe ser rechazada
    function test_CollectFareWithSig_RechazaFirmanteNoAutorizado() public {
        uint256 pasajeroPk = 0xB0B;
        uint256 nonce = operator.getNonce(vm.addr(pasajeroPk));

        bytes memory signature = _signCollectFare(pasajeroPk, pasajero, 101, 1, nonce);

        vm.expectRevert();
        operator.collectFareWithSig(pasajero, 101, 1, nonce, signature);
    }

    // TEST 6: Desactivar un bus y verificar que no pueda cobrar
    function test_DeactivateBus() public {
        // 1. Verificar que el bus puede cobrar inicialmente
        vm.prank(busValidador);
        operator.collectFare(pasajero, 101, 1);

        // 2. El admin desactiva el bus
        vm.prank(admin);
        operator.deactivateBus(busValidador);

        // 3. El bus intenta cobrar de nuevo y DEBE fallar
        vm.prank(busValidador);
        vm.expectRevert();
        operator.collectFare(pasajero, 101, 1);
    }
}
