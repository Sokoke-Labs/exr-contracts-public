// SPDX-License-Identifier: MIT

pragma solidity 0.8.9;

import "@openzeppelin/contracts/access/IAccessControl.sol";

import "@openzeppelin/contracts/token/ERC721/extensions/IERC721Enumerable.sol";

import "@openzeppelin/contracts/access/Ownable.sol";

import "@openzeppelin/contracts/security/Pausable.sol";

import "@openzeppelin/contracts/utils/Context.sol";

import "@openzeppelin/contracts/metatx/ERC2771Context.sol";

contract MockInterfaces {
    bytes4 public accessControlInterfaceId;
    bytes4 public pausableInterfaceId;
    bytes4 public contextInterfaceId;
    bytes4 public erc2771interfaceId;
    bytes4 public erc721enumerableId;

    constructor() {
        accessControlInterfaceId = type(IAccessControl).interfaceId;
        pausableInterfaceId = type(Pausable).interfaceId;
        contextInterfaceId = type(Context).interfaceId;
        erc2771interfaceId = type(ERC2771Context).interfaceId;
        erc721enumerableId = type(IERC721Enumerable).interfaceId;
    }
}
