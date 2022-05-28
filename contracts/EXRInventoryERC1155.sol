// SPDX-License-Identifier: MIT
pragma solidity 0.8.9;

import "@openzeppelin/contracts/token/ERC1155/extensions/ERC1155Burnable.sol";
import "@openzeppelin/contracts/token/ERC1155/extensions/ERC1155Supply.sol";
import "@openzeppelin/contracts/token/ERC1155/ERC1155.sol";
import "@openzeppelin/contracts/access/AccessControl.sol";
import "@openzeppelin/contracts/access/Ownable.sol";

error InventoryArrayLengthMismatch();
error InventoryNonExistentToken();
error InventoryTokenExists();
error InventoryEmptyURI();

/**
 * @title   EXR Inventory
 * @author  RacerDev
 * @notice  EXRInventory tokens are in-game utility items for Exiled Racers, an NFT-based racing game.
 * @dev     Minted should take place via an external contract that has the necessary Role assigned. The external
 *          contract should contain the logic for token distribution.
 */
contract EXRInventory is ERC1155Burnable, ERC1155Supply, Ownable, AccessControl {
    bytes32 public constant SYS_ADMIN_ROLE = keccak256("SYS_ADMIN_ROLE");
    bytes32 public constant MINTER_ROLE = keccak256("MINTER_ROLE");

    string public constant name = "EXR Inventory";
    string public constant symbol = "EXRI";

    string fallbackURI; // shared by all unrevealed inventory items

    mapping(uint256 => string) _itemURIs;

    event FallbackUriUpdated(string uri);
    event TokenUriUpdated(uint256 id, string uri);
    event InventorySetBatchTokenURIs();

    constructor(string memory fallbackURI_) ERC1155("") {
        _grantRole(DEFAULT_ADMIN_ROLE, msg.sender);
        _grantRole(SYS_ADMIN_ROLE, msg.sender);
        fallbackURI = fallbackURI_;
    }

    /*
     * ===================================== EXTERNAL
     */

    /**
     * @notice  Allows an Admin user to mint any amount of any token ID to an address
     * @param   recipient   The address to mint the tokens to
     * @param   id  The token ID to mint
     * @param   qty The number of tokens to mint
     */
    function adminMint(
        address recipient,
        uint256 id,
        uint256 qty
    ) external onlyRole(SYS_ADMIN_ROLE) {
        _mint(recipient, id, qty, "");
    }

    /**
     * @notice  Allows a caller with the appropriate role to mint a token
     * @dev     Caller should be a contract address in most circumstances
     * @param   recipient   The address to mint the tokens to
     * @param   id  The token ID to mint
     * @param   qty The number of tokens to mint
     */
    function mint(
        address recipient,
        uint256 id,
        uint256 qty
    ) external onlyRole(MINTER_ROLE) {
        _mint(recipient, id, qty, "");
    }

    /**
     * @notice  Allows a caller with the appropriate role to batch mint tokens
     * @dev     Caller should be a contract address in most circumstances
     * @param   recipient   The address to mint the tokens to
     * @param   ids  An array of IDs to mint
     * @param   amounts Array of quantities of the ID at the corresponding index in the `ids` array to mint
     */
    function mintBatch(
        address recipient,
        uint256[] calldata ids,
        uint256[] calldata amounts,
        bytes calldata data
    ) external onlyRole(MINTER_ROLE) {
        if (ids.length != amounts.length) revert InventoryArrayLengthMismatch();
        _mintBatch(recipient, ids, amounts, data);
    }

    /*
     * ===================================== EXTERNAL | PUBLIC
     */

    /**
     * @notice  Return the metadata URI for a given token ID
     * @dev     the {fallbackURI} is shared by token IDs without a dedicated metadata URI
     * @param   id The token ID to retrieve the token URI for
     * @return  the URI where the token's metadata is located
     */
    function uri(uint256 id) public view override returns (string memory) {
        if (!exists(id)) revert InventoryNonExistentToken();
        return bytes(_itemURIs[id]).length > 0 ? _itemURIs[id] : fallbackURI;
    }

    /*
     * ===================================== EXTERNAL | ADMIN
     */

    /**
     * @notice  Allows an Admin user to set a default fallback URI
     * @dev     The {fallbackURI} is shared by every token ID that has not had a dedicated URI assigned
     * @param   fallbackUri_ The URI where the fallback metadata is located
     */
    function setFallbackURI(string memory fallbackUri_) external onlyRole(SYS_ADMIN_ROLE) {
        if (bytes(fallbackUri_).length == 0) revert InventoryEmptyURI();
        fallbackURI = fallbackUri_;
        emit FallbackUriUpdated(fallbackUri_);
    }

    /**
     * @notice  Allows an Admin user to set a per-token URI
     * @dev     Allow for an empty URI, to allow the token with `id` to reset to use the {fallbackURI}
     * @param   id  The token ID to set the URI for
     * @param   tokenUri the URI where the specific token's metadata is retrieved from
     */
    function setTokenURI(uint256 id, string calldata tokenUri) external onlyRole(SYS_ADMIN_ROLE) {
        _itemURIs[id] = tokenUri;
        emit TokenUriUpdated(id, tokenUri);
    }

    /**
     * @notice  Allows an Admin user to set URIs for multiple tokens in a single call
     * @dev     Allow `tokenUris` array to contain empty URIs, to allow the token with `id` to reset to use the {fallbackURI}
     * @param   tokenIds  The token ID to set the URI for
     * @param   tokenUris the URI where the specific token's metadata is retrieved from
     */
    function batchSetTokenURIs(uint256[] calldata tokenIds, string[] calldata tokenUris)
        external
        onlyRole(SYS_ADMIN_ROLE)
    {
        if (tokenIds.length != tokenUris.length) revert InventoryArrayLengthMismatch();
        for (uint256 i; i < tokenIds.length; i++) {
            _itemURIs[tokenIds[i]] = tokenUris[i];
        }
        emit InventorySetBatchTokenURIs();
    }

    /*
     * ===================================== OVERRIDES
     */
    function _beforeTokenTransfer(
        address operator,
        address from,
        address to,
        uint256[] memory ids,
        uint256[] memory amounts,
        bytes memory data
    ) internal override(ERC1155, ERC1155Supply) {
        super._beforeTokenTransfer(operator, from, to, ids, amounts, data);
    }

    function supportsInterface(bytes4 interfaceId)
        public
        view
        override(ERC1155, AccessControl)
        returns (bool)
    {
        return super.supportsInterface(interfaceId);
    }
}
