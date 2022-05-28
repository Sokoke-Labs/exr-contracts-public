// SPDX-License-Identifier: MIT

pragma solidity 0.8.9;

import "@openzeppelin/contracts/utils/Strings.sol";

contract MockExternalRenderer {
    using Strings for uint256;

    string _baseURI;

    constructor(string memory uri) {
        _baseURI = uri;
    }

    function getTokenMetadata(uint256 tokenId) external view returns (string memory) {
        return string(abi.encodePacked(_baseURI, "/", tokenId.toString()));
    }
}
