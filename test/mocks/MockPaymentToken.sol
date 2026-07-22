// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";

/**
 * @title MockPaymentToken
 * @author Via Network
 * @notice Stand-in de COPm para tests y despliegues locales en Anvil.
 */
contract MockPaymentToken is ERC20 {
    constructor() ERC20("Mock COPm", "mCOPm") {}

    function mint(address to, uint256 amount) external {
        _mint(to, amount);
    }
}
