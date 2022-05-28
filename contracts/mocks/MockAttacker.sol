// SPDX-License-Identifier: MIT
pragma solidity 0.8.9;

struct Coupon {
    bytes32 r;
    bytes32 s;
    uint8 v;
}

interface IInventoryController {
    function claimRewardItems(
        bytes32 seed,
        uint256 qty,
        Coupon calldata coupon
    ) external;
}

contract Attacker {
    IInventoryController controller;

    constructor(address _target) {
        controller = IInventoryController(_target);
    }

    function claim(
        bytes32 seed,
        uint256 qty,
        Coupon calldata coupon
    ) external {
        controller.claimRewardItems(seed, qty, coupon);
    }

    function setTarget(address target) external {
        controller = IInventoryController(target);
    }
}
