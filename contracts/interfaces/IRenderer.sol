// SPDX-License-Identifier: MIT
pragma solidity 0.8.9;

interface IRenderer {
    function getTokenMetadata(uint256 tokenId) external view returns (string memory);
}
