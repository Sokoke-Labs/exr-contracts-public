// SPDX-License-Identifier: MIT
pragma solidity 0.8.9;

import "@openzeppelin/contracts/security/Pausable.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "./extensions/ERC721Fragmentable.sol";

error GameAssetTokenAlreadyMinted(uint256 tokenId);
error GameAssetTokenDoesNotExist(uint256 tokenId);
error GameAssetInvalidFragment(uint256 fragment);
error GameAssetFragmentTokenPoolSupplyExceeded();
error GameAssetTokenIdReserved(uint256 tokenId);
error GameAssetReservedSupplyExceeded();
error GameAssetInvalidFragmentTokenId();
error GameAssetTokenIdNotReserved();
error GameAssetZeroAddress();
error GameAssetInvalidSeed();
error GameAssetZeroCount();

/**
 * @title   EXR Game Asset
 * @author  RacerDev
 * @notice  EXRGameAsset tokens are in-game assets for Exiled Racers, an NFT-based racing game set in space.
 *          The NFTs double as traditional collectibles, in addition to serving as in-game items.
 * @dev     The contract inherits from ERC721Fragmentable, which allows the collection to be
 *          broken into fragments and the collection released in phases.
 * @dev     The UX is designed in such a way minting is not allowed directly from the contract.
 *          Mint functions are exposed only to other contracts via interfaces that are Access Controlled.
 */
contract EXRGameAsset is ERC721Fragmentable, Pausable {
    bytes32 constant MINTER_ROLE = keccak256("MINTER_ROLE");
    bytes32 constant PAUSER_ROLE = keccak256("PAUSER_ROLE");

    mapping(uint256 => uint256) public idToFragments;

    event GameAssetMinted(address indexed recipient, uint256 indexed fragment, uint256 tokenId);

    constructor(
        string memory name,
        string memory symbol,
        string memory defaultUri
    ) ERC721(name, symbol) ERC721Fragmentable(defaultUri) {
        _grantRole(DEFAULT_ADMIN_ROLE, msg.sender);
        _grantRole(MINTER_ROLE, msg.sender);
        _grantRole(PAUSER_ROLE, msg.sender);
    }

    /*
     * ===================================== EXTERNAL
     */

    /**
     * @notice  Mints one or more tokens
     * @dev     Function is intended to be called by other contracts, not by dApps
     * @dev     The seed's validity should be checked in the calling contract
     * @dev     There is no randomness like VRF available, so the verified seed is used instead
     * @param   recipient address to mint token to
     * @param   count number of tokens to mint
     * @param   fragment fragment of the collection that the token belongs to
     * @param   seed random seed provided by the caller
     */
    function mint(
        address recipient,
        uint256 count,
        uint8 fragment,
        bytes32 seed
    ) external whenNotPaused onlyRole(MINTER_ROLE) {
        if (recipient == address(0)) revert GameAssetZeroAddress();
        if (count == 0) revert GameAssetZeroCount();

        Fragment memory assetFragment = fragments[fragment];
        if (assetFragment.status != 1) revert GameAssetInvalidFragment(fragment);
        if (assetFragment.publicTokens.issuedCount + count > assetFragment.publicTokens.supply)
            revert GameAssetFragmentTokenPoolSupplyExceeded();

        for (uint256 i; i < count; i++) {
            uint256 tokenId = issueRandomId(fragment, seed);

            if (tokenId < assetFragment.firstTokenId + assetFragment.reservedTokens.supply)
                revert GameAssetTokenIdReserved({tokenId: tokenId});

            if (tokenId > assetFragment.firstTokenId + assetFragment.supply - 1)
                revert GameAssetInvalidFragmentTokenId();

            _createAndMintGameAsset(recipient, tokenId, fragment);
        }
    }

    /**
     * @notice  Mint tokens with IDs that have been reserved and are not public available
     * @dev     Allows admin to mint speficic Ids for a given fragment to a known recipient
     * @param   recipient address to mint to
     * @param   tokenId ID to mint
     * @param   fragment the fragment the token ID belongs to
     */
    function mintReserved(
        address recipient,
        uint256 tokenId,
        uint8 fragment
    ) external whenNotPaused onlyRole(MINTER_ROLE) {
        if (_exists(tokenId)) revert GameAssetTokenAlreadyMinted({tokenId: tokenId});

        Fragment storage assetFragment = fragments[fragment];
        if (assetFragment.status != 1) revert GameAssetInvalidFragment({fragment: fragment});

        if (assetFragment.reservedTokens.issuedCount >= assetFragment.reservedTokens.supply)
            revert GameAssetReservedSupplyExceeded();

        if (
            tokenId < assetFragment.firstTokenId ||
            tokenId > (assetFragment.firstTokenId + assetFragment.reservedTokens.supply) - 1
        ) revert GameAssetTokenIdNotReserved();

        fragments[fragment].reservedTokens.issuedCount++;
        _createAndMintGameAsset(recipient, tokenId, fragment);
    }

    /**
     * @notice  Pause the contract
     * @dev     Should only be used in emergency situations
     */
    function pause() external onlyRole(PAUSER_ROLE) {
        _pause();
    }

    /**
     * @notice  Unpause the contract
     * @dev     Used once any issues have been resolved
     */
    function unpause() external onlyRole(PAUSER_ROLE) {
        _unpause();
    }

    /*
     * ===================================== INTERNAL
     */

    /**
        @dev mints an asset and binds the token ID to the fragment ID
        @param to address to mint token to
        @param id ID to mint
        @param fragment fragment of the collection that the token belongs to
    */
    function _createAndMintGameAsset(
        address to,
        uint256 id,
        uint8 fragment
    ) internal {
        idToFragments[id] = fragment;
        _mint(to, id);
        emit GameAssetMinted(to, fragment, id);
    }

    /*
     * ===================================== OVERRIDES
     */

    /**
     * @dev     Fetches the {tokenURI} for the fragment the token belongs to. The fragment is
     *          is retrieved using the token ID.
     * @param   tokenId token ID to get the URI for
     * @return  the URL to the token metadata file
     */
    function tokenURI(uint256 tokenId) public view virtual override returns (string memory) {
        if (!_exists(tokenId)) revert GameAssetTokenDoesNotExist({tokenId: tokenId});

        uint256 fragment = idToFragments[tokenId];

        return _fragmentTokenURI(fragment, tokenId);
    }

    function _beforeTokenTransfer(
        address from,
        address to,
        uint256 tokenId
    ) internal override(ERC721Enumerable) whenNotPaused {
        super._beforeTokenTransfer(from, to, tokenId);
    }
}
