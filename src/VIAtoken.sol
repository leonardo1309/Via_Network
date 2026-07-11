// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import {AccessControl} from "@openzeppelin/contracts/access/AccessControl.sol";

contract VIAToken is ERC20, AccessControl {
    bytes32 public constant MINTER_ROLE = keccak256("MINTER_ROLE");
    bytes32 public constant OPERATOR_ROLE = keccak256("OPERATOR_ROLE");
    address public operator = 0x70997970C51812dc3A010C7d01b50e0d17dc79C8; // Dirección del contrato del operador (bus)

    constructor() ERC20("VIA Network", "VIA") {
        _mint(msg.sender, 1000000 * 10 ** decimals()); // Opcional: Mint inicial para el deployer
        _grantRole(DEFAULT_ADMIN_ROLE, msg.sender);
        _grantRole(MINTER_ROLE, msg.sender);
        _grantRole(OPERATOR_ROLE, msg.sender);
    }

    // Para recargar saldo al usuario (Puntos físicos o App)
    function mint(address to, uint256 amount) external onlyRole(MINTER_ROLE) {
        _mint(to, amount);
    }

    // El bus llama a esta función para cobrar
    function spend(address user, uint256 amount) external onlyRole(OPERATOR_ROLE) {
        _burn(user, amount);
    }
}