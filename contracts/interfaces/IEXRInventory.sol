// SPDX-License-Identifier: MIT
pragma solidity 0.8.9;

interface IEXRInventory {
    function mintBatch(
        address to,
        uint256[] memory ids,
        uint256[] memory amounts,
        bytes memory data
    ) external;
}
