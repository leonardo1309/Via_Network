// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {AccessControl} from "@openzeppelin/contracts/access/AccessControl.sol";
import {EIP712} from "@openzeppelin/contracts/utils/cryptography/EIP712.sol";
import {ECDSA} from "@openzeppelin/contracts/utils/cryptography/ECDSA.sol";

/*//////////////////////////////////////////////////////////////////////
                                 ERRORS
//////////////////////////////////////////////////////////////////////*/
error VIA_Operator__ZonaNoConfigurada();
error VIA_Operator__FirmanteNoAutorizado();
error VIA_Operator__NonceInvalido();

/**
 * @title VIA_Operator
 * @author Via Network
 * @notice Cobra pasajes de transporte publico descontando el stablecoin de pago (p.ej. COPm)
 * directamente de la wallet del pasajero hacia la wallet de la empresa de transporte.
 * @dev El contrato nunca retiene saldo: cada cobro es un `transferFrom` directo pasajero -> tesoreria.
 * El validador fisico (ESP32) autoriza cada cobro firmando un mensaje EIP-712 fuera de cadena
 * (`collectFareWithSig`); cualquier relayer puede retransmitirlo y pagar el gas, pero no puede
 * fabricar un cobro que el validador no haya firmado. `collectFare` sigue disponible para que el
 * propio validador envie la transaccion directamente, pagando su gas en CELO nativo.
 */
contract VIA_Operator is AccessControl, EIP712 {
    using SafeERC20 for IERC20;

    /*//////////////////////////////////////////////////////////////////////
                               TYPE DECLARATIONS
    //////////////////////////////////////////////////////////////////////*/
    // (ninguno)

    /*//////////////////////////////////////////////////////////////////////
                               STATE VARIABLES
    //////////////////////////////////////////////////////////////////////*/
    bytes32 public constant VALIDATOR_ROLE = keccak256("VALIDATOR_ROLE");

    /// @dev keccak256("CollectFare(address user,uint256 busId,uint256 zoneId,uint256 nonce)")
    bytes32 private constant COLLECT_FARE_TYPEHASH =
        keccak256("CollectFare(address user,uint256 busId,uint256 zoneId,uint256 nonce)");

    /// @dev Stablecoin de pago (COPm en mainnet; un stand-in como USDm mientras COPm no tenga
    /// despliegue v3 en la testnet que se use).
    IERC20 private immutable i_paymentToken;

    /// @dev Wallet de la empresa de transporte que recibe los pasajes cobrados.
    address private s_treasury;

    /// @dev precio por zona (1 = Local, 2 = Regional), en la unidad minima del token de pago.
    mapping(uint256 zoneId => uint256 price) private s_zonePrices;

    /// @dev nonce por validador, para que un relayer no pueda reenviar (replay) la misma firma.
    mapping(address validator => uint256 nonce) private s_nonces;

    /*//////////////////////////////////////////////////////////////////////
                                    EVENTS
    //////////////////////////////////////////////////////////////////////*/
    event FarePaid(
        address indexed user, uint256 amount, uint256 indexed busId, uint256 indexed zoneId, uint256 timestamp
    );
    event ValidatorDeactivated(address indexed busAddress, uint256 timestamp);
    event TreasuryUpdated(address indexed oldTreasury, address indexed newTreasury);

    /*//////////////////////////////////////////////////////////////////////
                                  FUNCTIONS
    //////////////////////////////////////////////////////////////////////*/

    /**
     * @notice Despliega el operador de cobro de pasajes.
     * @param _paymentToken Direccion del stablecoin usado para pagar los pasajes (COPm en mainnet).
     * @param _treasury Wallet de la empresa de transporte que recibe los pasajes cobrados.
     */
    constructor(address _paymentToken, address _treasury) EIP712("VIA_Operator", "1") {
        _grantRole(DEFAULT_ADMIN_ROLE, msg.sender);
        i_paymentToken = IERC20(_paymentToken);
        s_treasury = _treasury;

        s_zonePrices[1] = 1500; // Urbano
        s_zonePrices[2] = 5200; // Chia-Bogota
    }

    /// @notice El validador cobra el pasaje directamente, pagando su propio gas en CELO nativo.
    /// @param _user Wallet del pasajero a quien se le descuenta el pasaje.
    /// @param _busId Identificador del bus que realiza el cobro.
    /// @param _zoneId Zona tarifaria del viaje.
    function collectFare(address _user, uint256 _busId, uint256 _zoneId) external onlyRole(VALIDATOR_ROLE) {
        _collectFare(_user, _busId, _zoneId);
    }

    /**
     * @notice Retransmite un cobro autorizado por firma EIP-712 de un validador.
     * @dev Cualquiera puede llamar esta funcion (p.ej. un relayer que paga el gas en USDm/COPm);
     * la autorizacion viene de la firma, no de quien envia la transaccion.
     * @param _user Wallet del pasajero a quien se le descuenta el pasaje.
     * @param _busId Identificador del bus que realiza el cobro.
     * @param _zoneId Zona tarifaria del viaje.
     * @param _nonce Nonce esperado del validador firmante (anti-replay).
     * @param _signature Firma EIP-712 del validador sobre (user, busId, zoneId, nonce).
     */
    function collectFareWithSig(
        address _user,
        uint256 _busId,
        uint256 _zoneId,
        uint256 _nonce,
        bytes calldata _signature
    ) external {
        bytes32 structHash = keccak256(abi.encode(COLLECT_FARE_TYPEHASH, _user, _busId, _zoneId, _nonce));
        bytes32 digest = _hashTypedDataV4(structHash);
        address signer = ECDSA.recoverCalldata(digest, _signature);

        if (!hasRole(VALIDATOR_ROLE, signer)) revert VIA_Operator__FirmanteNoAutorizado();
        if (_nonce != s_nonces[signer]) revert VIA_Operator__NonceInvalido();
        s_nonces[signer]++;

        _collectFare(_user, _busId, _zoneId);
    }

    /// @notice Actualiza el precio de una zona tarifaria.
    /// @param _zoneId Zona a actualizar.
    /// @param _amount Nuevo precio, en la unidad minima del token de pago.
    function setZonePrice(uint256 _zoneId, uint256 _amount) external onlyRole(DEFAULT_ADMIN_ROLE) {
        s_zonePrices[_zoneId] = _amount;
    }

    /// @notice Actualiza la wallet de la empresa de transporte que recibe los pasajes.
    /// @param _treasury Nueva wallet de tesoreria.
    function setTreasury(address _treasury) external onlyRole(DEFAULT_ADMIN_ROLE) {
        emit TreasuryUpdated(s_treasury, _treasury);
        s_treasury = _treasury;
    }

    /// @notice Desactiva un bus de inmediato si hay sospecha de robo o mal uso del validador.
    /// @param _busAddress Wallet del validador (bus) a desactivar.
    function deactivateBus(address _busAddress) external onlyRole(DEFAULT_ADMIN_ROLE) {
        revokeRole(VALIDATOR_ROLE, _busAddress);
        emit ValidatorDeactivated(_busAddress, block.timestamp);
    }

    /// @dev Descuenta el pasaje: `transferFrom` directo pasajero -> tesoreria. El contrato nunca
    /// retiene el saldo, por lo que el pasajero debe haber aprobado previamente este contrato.
    function _collectFare(address _user, uint256 _busId, uint256 _zoneId) private {
        uint256 price = s_zonePrices[_zoneId];
        if (price == 0) revert VIA_Operator__ZonaNoConfigurada();

        i_paymentToken.safeTransferFrom(_user, s_treasury, price);

        emit FarePaid(_user, price, _busId, _zoneId, block.timestamp);
    }

    /*//////////////////////////////////////////////////////////////////////
                          VIEW & PURE FUNCTIONS (GETTERS)
    //////////////////////////////////////////////////////////////////////*/

    /// @notice Devuelve el precio configurado para una zona tarifaria.
    function getZonePrice(uint256 _zoneId) external view returns (uint256) {
        return s_zonePrices[_zoneId];
    }

    /// @notice Devuelve el siguiente nonce esperado para un validador (para que firme su proximo cobro).
    function getNonce(address _validator) external view returns (uint256) {
        return s_nonces[_validator];
    }

    /// @notice Devuelve la wallet de tesoreria (empresa de transporte) que recibe los pasajes.
    function getTreasury() external view returns (address) {
        return s_treasury;
    }

    /// @notice Devuelve el stablecoin usado para pagar los pasajes.
    function getPaymentToken() external view returns (IERC20) {
        return i_paymentToken;
    }
}
