// SPDX-License-Identifier: MIT

pragma solidity 0.8.9;

import "@openzeppelin/contracts/token/ERC721/extensions/ERC721Enumerable.sol";
import "@openzeppelin/contracts/access/AccessControl.sol";
import "@openzeppelin/contracts/token/ERC721/ERC721.sol";
import "@openzeppelin/contracts/access/Ownable.sol";

import "@openzeppelin/contracts/utils/Strings.sol";

import "../interfaces/IRenderer.sol";

error FragmentNotFound(uint256 fragment);
error FragmentExceedsCollectionSupply();
error FragmentsTokenIdsNotSequential();
error FragmentTokenSupplyExceeded();
error FragmentSupplyMismatch();
error FragmentNotSequential();
error FragmentInvalidSupply();
error FragmentZeroAddress();
error FragmentInvalid();
error TokenPoolEmpty();
error FragmentExists();
error FragmentLocked();

/**
 * @title   Collection fragment
 * @author  RacerDev
 * @notice  This contract is the base for a novel extension to the ERC721 standard that allows a
 *          collection to be partitioned, or fragmented, into smaller fragments.  Each fragment is allocated
 *          its own supply and defines the range of token IDs that it contains. In addition, each
 *          fragment has its own unique metadata storage URI that points to an IFPS collection containing
 *          the collection's metadata files.
 * @notice  The extension was created to allow for NFT collections to be extended, or released in phases,
 *          as opposed to having all tokens minted druing a single event.  It provides flexibility to add different/additional
 *          assets that are part of the same collection, but do not share an metadata origin with the other fragments.
 * @dev     Fragments can have an external renderer contract attached to return a `tokenURI` containing purely on-chain data
 * @dev     A Fragment is capable of issuing randomized token IDs at mint time, with the aid of seed provided by the caller. Verifying
 *          the validity of the seed is left up to the caller (usually another contract).
 */

abstract contract ERC721Fragmentable is ERC721Enumerable, Ownable, AccessControl {
    using Strings for uint256;

    bytes32 public constant SYS_ADMIN_ROLE = keccak256("SYS_ADMIN_ROLE");
    bytes32 public constant FRAGMENT_CREATOR_ROLE = keccak256("FRAGMENT_CREATOR_ROLE");

    struct TokenPool {
        uint64 issuedCount;
        uint64 startId;
        uint64 supply;
    }

    struct Fragment {
        uint8 status;
        uint8 locked;
        uint8 fragmentId;
        uint64 firstTokenId;
        uint64 supply;
        string baseURI;
        IRenderer renderer;
        TokenPool reservedTokens;
        TokenPool publicTokens;
    }

    uint256 public constant MAX_SUPPLY = 9000;
    string public fallbackURI;

    uint256 public fragmentCount;

    mapping(uint256 => Fragment) public fragments;
    mapping(uint256 => mapping(uint256 => uint256)) public fragmentPoolTokenMatrix;

    event FragmentMetadataLocked(uint256 fragment);
    event FragmentCreated(uint256 id, uint256 supply);
    event FragmentExternalRendererSet(uint256 fragment, address renderContract);
    event FragmentMetadataUpdated(uint256 fragmentNumber, string uri);

    constructor(string memory uri) {
        _grantRole(DEFAULT_ADMIN_ROLE, msg.sender);
        _grantRole(SYS_ADMIN_ROLE, msg.sender);
        fallbackURI = uri;
    }

    // =============================================== EXTERNAL | OWNER

    /**
     * @notice  Allows the owner of the contract to update the metadata URI for a given fragment
     * @dev     A fragment's metadata can only be updated if the fragment has not been locked. Once the fragment
     *          has been locked, the metdata for that fragment is permananetly frozen.
     * @param   fragmentNumber  The fragment's identifier in the collection.
     * @param   baseURI_  The content identifier for the fragment's metadata.
     */
    function updateFragmentMetadata(uint256 fragmentNumber, string calldata baseURI_)
        external
        onlyRole(SYS_ADMIN_ROLE)
    {
        if (fragments[fragmentNumber].status == 0) revert FragmentInvalid();
        if (fragments[fragmentNumber].locked == 1) revert FragmentLocked();

        fragments[fragmentNumber].baseURI = baseURI_;
        emit FragmentMetadataUpdated(fragmentNumber, baseURI_);
    }

    /**
     * @notice  Allows the contract owner to lock a fragment's metadata, permanently freezing it.
     * @dev     This action is irreversible.
     * @param   fragmentNumber the fragment's identifier in the collection.
     */
    function lockFragmentMetadata(uint256 fragmentNumber) external onlyRole(SYS_ADMIN_ROLE) {
        if (fragments[fragmentNumber].status == 0) revert FragmentInvalid();
        fragments[fragmentNumber].locked = 1;
        emit FragmentMetadataLocked(fragmentNumber);
    }

    /**
     * @notice  Allows an Admin to assign an external on-chain renderer to the fragment
     * @dev     Once a renderer has been assigned, the contract cannot go back to using the {_baseURI}
     * @param   fragmentNumber the fragment's identifier in the collection.
     * @param   renderContract the address for the renderer's contract interface
     */
    function setRenderer(uint256 fragmentNumber, address renderContract)
        external
        onlyRole(SYS_ADMIN_ROLE)
    {
        if (renderContract == address(0)) revert FragmentZeroAddress();
        if (fragments[fragmentNumber].status == 0) revert FragmentInvalid();
        if (fragments[fragmentNumber].locked == 1) revert FragmentLocked();
        fragments[fragmentNumber].renderer = IRenderer(renderContract);
        emit FragmentExternalRendererSet(fragmentNumber, renderContract);
    }

    // =============================================== EXTERNAL

    /**
     * @notice  Checks whether a fragment has been created
     * @dev     convenience function for checking if an external contract is interacting with
     *          a valid fragment.
     * @param   fragmentNumber  The fragment's identifier in the collection.
     */
    function fragmentExists(uint256 fragmentNumber) external view returns (bool) {
        return fragments[fragmentNumber].status == 1;
    }

    /**
     * @notice  Creates a new fragment in the collection.
     * @dev     Fragments can only be created by an account with the FRAGMENT_CREATOR_ROLE assigned.
     *          The function contains checks to ensure that the fragment created follows on from the previous,
     *          that the supply is consistent with the IDs, and that the first ID of the fragment follows
     *          the last ID of the previous.
     * @dev     A fragment contains two `TokenPools`, one for publicly available tokens, and one for reserved tokens
     * @param   id              The fragment's identifier in the collection.
     * @param   fragmentSupply  The total number of tokens in the fragment.
     * @param   firstId         The Token ID of the first token in the fragment.
     * @param   reserved        The number of reserved tokens in the collection.
     */
    function createFragment(
        uint8 id,
        uint64 fragmentSupply,
        uint64 firstId,
        uint64 reserved
    ) external onlyRole(FRAGMENT_CREATOR_ROLE) {
        if (fragmentSupply <= 1) revert FragmentInvalidSupply();
        if (firstId + fragmentSupply - 1 >= MAX_SUPPLY) revert FragmentExceedsCollectionSupply();
        if (reserved > fragmentSupply) revert FragmentTokenSupplyExceeded();
        if (fragments[id].status == 1) revert FragmentExists();

        if (id > 0) {
            Fragment memory previousFragment = fragments[id - 1];
            if (id != previousFragment.fragmentId + 1) revert FragmentNotSequential();
            if (firstId != previousFragment.firstTokenId + previousFragment.supply)
                revert FragmentsTokenIdsNotSequential();
        }
        fragmentCount++;
        fragments[id] = Fragment({
            status: 1,
            locked: 0,
            fragmentId: id,
            firstTokenId: firstId,
            supply: fragmentSupply,
            baseURI: "",
            renderer: IRenderer(address(0)),
            publicTokens: TokenPool({
                issuedCount: 0,
                startId: firstId + reserved,
                supply: fragmentSupply - reserved
            }),
            reservedTokens: reserved > 0
                ? TokenPool({issuedCount: 0, startId: firstId, supply: reserved})
                : TokenPool(0, 0, 0)
        });

        emit FragmentCreated(id, fragmentSupply);
    }

    /**
     * @notice  Returns all the token IDs for a given address.
     * @dev     Uses {tokenOfOwnerByIndex} to enumerate the tokens owned by the `_address` provided.
     * @return  The token IDs owned by the address provided.
     */
    function walletOfOwner(address _owner) external view returns (uint256[] memory) {
        uint256 tokenCount = balanceOf(_owner);

        uint256[] memory tokenIds = new uint256[](tokenCount);
        for (uint256 i = 0; i < tokenCount; i++) {
            tokenIds[i] = tokenOfOwnerByIndex(_owner, i);
        }

        return tokenIds;
    }

    // =============================================== INTERNAL

    /**
     * @notice  Issues a randomly assigned token ID from the pool of remaining IDs in the fragment
     * @dev     Uses the {fragmentPoolTokenMatrix} mapping to keep track of the minted IDs for each fragment, which
     *          is an implementation of the Fisher-Yates shuffle
     * @param   fragment The fragment identifier indicating which fragment the token is for
     * @param   seed A 32-byte seed to improve randomness (this should be verified before reaching this function)
     * @return  A random token ID offset from the start of the designated fragment's public token range
     */
    function issueRandomId(uint256 fragment, bytes32 seed) internal returns (uint256) {
        Fragment storage currentFragment = fragments[fragment];

        uint256 remaining = currentFragment.publicTokens.supply -
            currentFragment.publicTokens.issuedCount;
        if (remaining == 0) revert TokenPoolEmpty();

        // returns a random number between 0 and the number of tokens remaining - 1, this will be
        // used as the random ID if the slot in the matrix corresponding to the index is empty
        uint256 randomIndex = uint256(
            keccak256(abi.encodePacked(block.basefee, blockhash(block.number - 1), seed))
        ) % remaining;

        // If the matrix is empty at the given random index (slot), we use the index as the token ID.
        // However, if the slot contains an ID, we'll assign that instead.

        uint256 offset = fragmentPoolTokenMatrix[fragment][randomIndex] == 0
            ? randomIndex
            : fragmentPoolTokenMatrix[fragment][randomIndex];

        currentFragment.publicTokens.issuedCount++;

        uint256 temp = fragmentPoolTokenMatrix[fragment][remaining - 1];

        if (temp == 0) {
            fragmentPoolTokenMatrix[fragment][randomIndex] = remaining - 1;
        } else {
            fragmentPoolTokenMatrix[fragment][randomIndex] = temp;
            delete fragmentPoolTokenMatrix[fragment][remaining - 1]; // small gas refund
        }

        uint256 tokenId = currentFragment.publicTokens.startId + offset;
        return tokenId;
    }

    /**
     * @notice  Retrieves the fragment-specific token URI
     * @dev     If the fragment's metadata hash has not been set (ie. it's empty), the
     *          collections {fallbackURI} is returned.
     * @dev     Uses the `fragment` parameter to determine which fragment the `tokenId` belongs to
     * @param   fragment The fragment's identifier in the collection
     * @param   tokenId The token ID to retrieve the metadata for
     * @return  The token URI for the fragment if it's been set, the {fallbackURI} if not.
     */
    function _fragmentTokenURI(uint256 fragment, uint256 tokenId)
        internal
        view
        returns (string memory)
    {
        if (fragments[fragment].status == 0) revert FragmentNotFound({fragment: fragment});
        if (fragments[fragment].renderer != IRenderer(address(0))) {
            return fragments[fragment].renderer.getTokenMetadata(tokenId);
        }

        return
            bytes(fragments[fragment].baseURI).length > 0
                ? string(abi.encodePacked(fragments[fragment].baseURI, "/", tokenId.toString()))
                : fallbackURI;
    }

    // =============================================== OVERRIDES

    function supportsInterface(bytes4 interfaceId)
        public
        view
        virtual
        override(AccessControl, ERC721Enumerable)
        returns (bool)
    {
        return super.supportsInterface(interfaceId);
    }
}
