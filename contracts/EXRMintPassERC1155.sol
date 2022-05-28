// SPDX-License-Identifier: MIT

pragma solidity 0.8.9;

import "@openzeppelin/contracts/token/ERC1155/extensions/ERC1155Burnable.sol";
import "@openzeppelin/contracts/token/ERC1155/extensions/ERC1155Supply.sol";
import "@openzeppelin/contracts/access/AccessControl.sol";
import "@openzeppelin/contracts/access/Ownable.sol";

error MintpassNonExistentToken();
error PassArrayLengthMismatch();
error MintpassZeroLengthUri();
error MintpassInvalidToken();
error MintpassMissingRole();
error MintpassZeroAddress();
error MintpassZeroQty();
error InvalidTokenUri();

/**
 * @title   EXR Mint Pass
 * @author  RacerDev
 * @notice  EXRMintPass tokens can be exchanged for in-game assets such as Pilots, Racecraft, and Inventory Items
 * @dev     Users should not interact with this contract directly. All minting and burning should take place via
 *          contracts with the appropriate Roles permissions via assigned Roles.
 */
contract EXRMintPass is ERC1155Burnable, ERC1155Supply, Ownable, AccessControl {
    bytes32 public constant SYS_ADMIN_ROLE = keccak256("SYS_ADMIN_ROLE");
    bytes32 public constant MINTER_ROLE = keccak256("MINTER_ROLE");
    bytes32 public constant BURNER_ROLE = keccak256("BURNER_ROLE");

    uint256 constant pilotPassTokenId = 1;
    uint256 constant racecraftPassTokenId = 2;
    uint256 constant inventoryTokenId = 3;

    string public constant name = "EXR Mint Pass";
    string public constant symbol = "EXRMP";

    string public fallbackURI;

    mapping(uint256 => mapping(uint256 => uint256)) public tokenMintCountsByFragment;
    mapping(uint256 => mapping(address => uint256)) public addressToPilotPassClaimsByFragment;

    mapping(uint256 => uint256) public tokenBurnCounts;

    mapping(uint256 => string) _tokenURIs;

    event PassMinted(address indexed recipient, uint256 id, uint256 qty);
    event Airdrop(address indexed recipient, uint256 id, uint256 qty);
    event PassBurned(address indexed account, uint256 tokenId);
    event SalesMintBurnRoleGranted(address contractAddress);
    event TokenUriSet(string uri, uint256 id);
    event PilotRedeemed(address indexed user);
    event UpdatedFallbackURI(string uri);

    constructor(string memory fallbackURI_) ERC1155("") {
        _grantRole(DEFAULT_ADMIN_ROLE, msg.sender);
        _grantRole(SYS_ADMIN_ROLE, msg.sender);
        fallbackURI = fallbackURI_;
    }

    // ========================================= EXTERNAL

    /**
     * @notice  Mints a token
     * @dev     Can only be called by a caller with the MINTER_ROLE - should under usual circumstances
     *          be a contract
     * @param   recipient   Address to receive the token
     * @param   qty         Number of tokens to mint
     * @param   tokenId     Token ID of the token to mint
     * @param   fragment    The Fragment the Mint Pass is associated with
     */
    function mint(
        address recipient,
        uint256 qty,
        uint256 tokenId,
        uint256 fragment
    ) external onlyRole(MINTER_ROLE) {
        if (recipient == address(0)) revert MintpassZeroAddress();
        if (qty == 0) revert MintpassZeroQty();
        tokenMintCountsByFragment[fragment][tokenId] += qty;
        _mint(recipient, tokenId, qty, "");
        emit PassMinted(recipient, tokenId, qty);
    }

    /**
     * @notice  Exchange a Pilot Mintpass for a Racecraft and Inventory Mintpass
     * @dev     function called by sales contract in order to burn the mintpass, and to mint a token to be used later
     * @param   account address of the token owner
     * @param   fragment The Fragment the Mint Passes are assosciated with
     */
    function burnToRedeemPilot(address account, uint256 fragment) external onlyRole(BURNER_ROLE) {
        tokenBurnCounts[pilotPassTokenId]++;
        tokenMintCountsByFragment[fragment][racecraftPassTokenId]++;
        tokenMintCountsByFragment[fragment][inventoryTokenId]++;

        _burn(account, pilotPassTokenId, 1);
        emit PassBurned(account, pilotPassTokenId);

        _mint(account, racecraftPassTokenId, 1, "");
        emit PassMinted(account, racecraftPassTokenId, 1);

        _mint(account, inventoryTokenId, 1, "");
        emit PassMinted(account, inventoryTokenId, 1);
    }

    /**
     *   @notice generic burn function called externally by authorized contracts
     *   @param  account address of the token owner
     *   @param  tokenId ID of the token to burn
     */
    function authorizedBurn(address account, uint256 tokenId) external onlyRole(BURNER_ROLE) {
        tokenBurnCounts[tokenId]++;
        _burn(account, tokenId, 1);
        emit PassBurned(account, tokenId);
    }

    /**
     * @notice increments the count for the number of pilot mintpasses claimed per fragment
     * @param caller Address of the original msg.sender
     * @param fragment The fragment to which the claim belongs
     * @param qty The number of passes being claimed
     */
    function incrementPilotPassClaimCount(
        address caller,
        uint256 fragment,
        uint256 qty
    ) external onlyRole(MINTER_ROLE) {
        addressToPilotPassClaimsByFragment[fragment][caller] += qty;
    }

    // ========================================= EXTERNAL | OWNER

    /**
     * @notice  Allows an Admin to update the {fallbackURI}
     * @param   fallbackURI_ The URI to set
     */
    function updateFallbackURI(string calldata fallbackURI_) external onlyRole(SYS_ADMIN_ROLE) {
        if (bytes(fallbackURI_).length == 0) revert MintpassZeroLengthUri();
        fallbackURI = fallbackURI_;
        emit UpdatedFallbackURI(fallbackURI_);
    }

    /**
     * @notice  Allows an Admin user to set the token URI for a specific token ID
     * @dev     Allow an Admin to set the URI to an empty string to enable the {fallbackURI}
     * @param   id Token ID for which to set the URI
     * @param   tokenIdURI uri for the metadata
     */
    function setTokenUriById(uint256 id, string calldata tokenIdURI)
        external
        onlyRole(SYS_ADMIN_ROLE)
    {
        _tokenURIs[id] = tokenIdURI;
        emit TokenUriSet(tokenIdURI, id);
    }

    // ========================================= OVERRIDES

    /**
     *   @notice    returns the token URI for a specific id
     *   @dev       If the specific token ID's URI has not been set, return the fallbackURI
     *   @param id  token ID of the URI to return
     *   @return    The URI where the metadata can be retrieved from
     */
    function uri(uint256 id) public view override returns (string memory) {
        if (totalSupply(id) == 0) revert MintpassNonExistentToken();

        return bytes(_tokenURIs[id]).length > 0 ? _tokenURIs[id] : fallbackURI;
    }

    function supportsInterface(bytes4 interfaceId)
        public
        view
        virtual
        override(AccessControl, ERC1155)
        returns (bool)
    {
        return super.supportsInterface(interfaceId);
    }

    function _beforeTokenTransfer(
        address operator,
        address from,
        address to,
        uint256[] memory ids,
        uint256[] memory amounts,
        bytes memory data
    ) internal virtual override(ERC1155Supply, ERC1155) {
        super._beforeTokenTransfer(operator, from, to, ids, amounts, data);
    }
}
