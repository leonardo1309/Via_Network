// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {AccessControl} from "@openzeppelin/contracts/access/AccessControl.sol";
import {VIAToken} from "./VIAToken.sol"; 

contract VIA_Operator is AccessControl {

    bytes32 public constant VALIDATOR_ROLE = keccak256("VALIDATOR_ROLE");
    
    VIAToken public viaToken;
    
    // Precios por zona (1 = Local, 2 = Regional)
    mapping(uint256 => uint256) public zonePrices;

    event FarePaid(
        address indexed user, 
        uint256 amount, 
        uint256 indexed busId, 
        uint256 indexed zoneId, 
        uint256 timestamp
    );
    event ValidatorDeactivated(address indexed busAddress, uint256 timestamp);

    constructor(address _tokenAddress) {
        _grantRole(DEFAULT_ADMIN_ROLE, msg.sender);
        viaToken = VIAToken(_tokenAddress);
        
        // Precios iniciales (puedes ajustarlos luego)
        zonePrices[1] = 1500; // Urbano
        zonePrices[2] = 5200; // Chía-Bogotá
    }

    // Función que llama el validador del bus
    function collectFare(address _user, uint256 _busId, uint256 _zoneId) external onlyRole(VALIDATOR_ROLE) {
        uint256 price = zonePrices[_zoneId];
        require(price > 0, "Zona no configurada");

        viaToken.spend(_user, price);

        emit FarePaid(_user, price, _busId, _zoneId, block.timestamp);
    }

    // Para actualizar tarifas sin desplegar nuevos contratos
    function setZonePrice(uint256 _zoneId, uint256 _amount) external onlyRole(DEFAULT_ADMIN_ROLE) {
        zonePrices[_zoneId] = _amount;
    }

    /**
    * @dev Desactiva un bus de inmediato si hay sospecha de robo o mal uso.
    * Solo el Admin (tú) puede ejecutar esto.
    */
    function deactivateBus(address _busAddress) external onlyRole(DEFAULT_ADMIN_ROLE) {
    // Revocamos el rol para que collectFare() falle si este bus intenta llamar
        revokeRole(VALIDATOR_ROLE, _busAddress);
        emit ValidatorDeactivated(_busAddress, block.timestamp);
    }
}