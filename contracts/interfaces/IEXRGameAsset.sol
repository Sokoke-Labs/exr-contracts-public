// SPDX-License-Identifier: MIT
pragma solidity 0.8.9;

interface IEXRGameAsset {
    function mint(
        address recipient,
        uint256 count,
        uint8 fragment,
        bytes32 seed
    ) external;

    function createFragment(
        uint8 id,
        uint64 fragmentSupply,
        uint64 firstId,
        uint64 reserved
    ) external;

    function fragmentExists(uint256 fragmentNumber) external view returns (bool);
}
