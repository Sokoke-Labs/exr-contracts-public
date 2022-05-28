// SPDX-License-Identifier: MIT
pragma solidity 0.8.9;

import "@openzeppelin/contracts/security/ReentrancyGuard.sol";
import "@openzeppelin/contracts/metatx/ERC2771Context.sol";
import "@openzeppelin/contracts/access/AccessControl.sol";
import "@openzeppelin/contracts/security/Pausable.sol";
import "./interfaces/IEXRMintPass.sol";
import "./interfaces/IEXRInventory.sol";
import "./extensions/CouponSystem.sol";

error InventoryInsufficientPassBalance();
error InventoryCategoryExists();
error InventoryUnapprovedBurn();
error InventoryInvalidCoupon();
error InventoryZeroAddress();
error InventoryReusedSeed();

/**
 * @title   EXR Inventory Controller
 * @author  RacerDev
 * @notice  This contract controls the distribution of EXRInventory items for the EXR ecosystem.
 * @dev     Because Chainlink's VRF is not available at the time of development, random number
 *          generation is aided by a verifiably random seed generated off-chain.
 * @dev     This contract caters to the existing Inventory Items at the time of launch. If additional
 *          items need to be added, this contract should be replaced with a newer version.
 */
contract EXRInventoryController is
    ERC2771Context,
    AccessControl,
    Pausable,
    ReentrancyGuard,
    CouponSystem
{
    bytes32 public constant SYS_ADMIN_ROLE = keccak256("SYS_ADMIN_ROLE");
    bytes32 public constant PAUSER_ROLE = keccak256("PAUSER_ROLE");

    uint256 public constant inventoryPassId = 3;

    mapping(bytes32 => bool) public usedSeeds;

    struct Category {
        uint8 exists;
        uint8 id;
        uint8[9] tokenIds;
    }

    Category[] public categories;

    IEXRMintPass public mintpassContract;
    IEXRInventory public inventoryContract;

    event InventoryUpdateMintpassInterface(address contractAddress);
    event InventoryUpdateInventoryInterface(address contractAddress);
    event InventoryItemsClaimed(uint256[] ids, uint256[] amounts);
    event InventoryRewardClaimed(address indexed user, uint256 qty);
    event InventoryCategoryAdded(uint256 category);
    event InventoryCategoryRemoved(uint8 category);
    event InventoryCategoryDoesNotExist(uint8 category);
    event AdminSignerUpdated(address signer);

    constructor(address adminSigner, address trustedForwarder)
        CouponSystem(adminSigner)
        ERC2771Context(trustedForwarder)
    {
        _grantRole(DEFAULT_ADMIN_ROLE, msg.sender);
        _grantRole(SYS_ADMIN_ROLE, msg.sender);
        _grantRole(PAUSER_ROLE, msg.sender);
    }

    /*
     * ===================================== EXTERNAL
     */

    /**
     * @notice  Allow users with a valid coupon to claim Inventory Items
     * @dev     Mechanism for players to claim inventory items as a reward
     * @param   seed 32-byte hash of the random seed
     * @param   qty The number of inventory items to claim
     * @param   coupon The decoded r,s,v components of the signature
     */
    function claimRewardItems(
        bytes32 seed,
        uint256 qty,
        Coupon calldata coupon
    ) external whenNotPaused nonReentrant hasValidOrigin {
        if (usedSeeds[seed]) revert InventoryReusedSeed();

        usedSeeds[seed] = true;
        bytes32 digest = keccak256(
            abi.encode(address(this), block.chainid, CouponType.Reward, qty, seed, _msgSender())
        );
        if (!_verifyCoupon(digest, coupon)) revert InventoryInvalidCoupon();

        _claimRandomItems(seed, qty);
        emit InventoryRewardClaimed(_msgSender(), qty);
    }

    /**
     * @notice  Allows the holder of an Inventory Mint Pass to exchange it for Inventory Items
     * @dev     Caller must have a valid Coupon containing a seed distributed by the EXR API
     * @param   seed 32-byte hash of the random seed
     * @param   qty The number of inventory items to claim
     * @param   coupon The decoded r,s,v components of the signature
     */
    function burnToRedeemInventoryItems(
        bytes32 seed,
        uint256 qty,
        Coupon calldata coupon
    ) external whenNotPaused nonReentrant hasValidOrigin {
        if (mintpassContract.balanceOf(_msgSender(), inventoryPassId) == 0)
            revert InventoryInsufficientPassBalance();
        if (usedSeeds[seed]) revert InventoryReusedSeed();

        usedSeeds[seed] = true;
        bytes32 digest = keccak256(
            abi.encode(address(this), block.chainid, CouponType.Inventory, qty, seed, _msgSender())
        );
        if (!_verifyCoupon(digest, coupon)) revert InventoryInvalidCoupon();

        mintpassContract.authorizedBurn(_msgSender(), inventoryPassId);
        _claimRandomItems(seed, qty);
    }

    /*
     * ===================================== EXTERNAL | ADMIN
     */

    /**
     *   @notice    Allows an Admin user to create the {mintpassContract} interface
     *   @param     mintpass Address of the Mintpass contract
     */
    function setMintpassContract(address mintpass) external onlyRole(SYS_ADMIN_ROLE) {
        if (mintpass == address(0)) revert InventoryZeroAddress();
        mintpassContract = IEXRMintPass(mintpass);
        emit InventoryUpdateMintpassInterface(mintpass);
    }

    /**
     *   @notice    Allows an Admin user to create the {inventoryContract} interface
     *   @param     inventory Address of the Inventory Contract
     */
    function setInventoryContract(address inventory) external onlyRole(SYS_ADMIN_ROLE) {
        if (inventory == address(0)) revert InventoryZeroAddress();
        inventoryContract = IEXRInventory(inventory);
        emit InventoryUpdateInventoryInterface(inventory);
    }

    /**
     * @dev     Admin can replace signer public address from signer's keypair
     * @param   newSigner public address of the signer's keypair
     */
    function updateAdminSigner(address newSigner) external onlyRole(SYS_ADMIN_ROLE) {
        _replaceSigner(newSigner);
        emit AdminSignerUpdated(newSigner);
    }

    /**
     * @notice  Allows an Admin user to add a category of Inventory Items
     * @dev     Manually increments the category count required for looping through the categories
     * @param   categoryId the category index for accessing the {categoryToIds} array
     * @param   ids the token IDs to add to the category
     */
    function addCategory(uint8 categoryId, uint8[9] calldata ids)
        external
        onlyRole(SYS_ADMIN_ROLE)
    {
        for (uint256 i; i < categories.length; i++) {
            if (categories[i].id == categoryId) revert InventoryCategoryExists();
        }
        categories.push(Category({id: categoryId, exists: 1, tokenIds: ids}));
        emit InventoryCategoryAdded(categoryId);
    }

    /**
     * @notice  Retrieves a category, including its ID and the tokenIDs array
     * @dev     Convenience function for reviewing existing categories
     * @param   categoryId The ID of the category to be retrieved
     * @return  The category, along with its token IDs
     */
    function getCategory(uint256 categoryId) external view returns (Category memory) {
        return categories[categoryId];
    }

    /**
     * @notice  Allows an admin user to remove a category of inventory items
     * @dev     the {categories} array acts like an unordered list. Removing an item replaces it with
     *          the last item in the array and removes the redundant last item
     * @dev     The category identifier can be an integer greater than the length of the {categories}
     *          array
     * @param   category The ID of the category to remove (this is not the index in the array)
     */
    function removeCategory(uint8 category) external onlyRole(SYS_ADMIN_ROLE) {
        bool removed;
        for (uint256 i; i < categories.length; i++) {
            if (categories[i].id == category) {
                categories[i] = categories[categories.length - 1];
                categories.pop();
                removed = true;
                emit InventoryCategoryRemoved(category);
                break;
            }
        }

        if (!removed) {
            emit InventoryCategoryDoesNotExist(category);
        }
    }

    /**
     * @notice Allows a user with the PAUSER_ROLE to pause the contract
     * @dev    This can be used to deprecate the contract if it's replaced
     */
    function pause() external onlyRole(PAUSER_ROLE) {
        _pause();
    }

    /**
     *   @notice Allows a user with the PAUSER_ROLE to unpause the contract
     */
    function unpause() external onlyRole(PAUSER_ROLE) {
        _unpause();
    }

    /*
     * ===================================== INTERNAL
     */

    /**
     * @notice  Claim random tokens
     * @dev     Uses the verified seed along with block data to select random token IDs
     * @dev     {categories} acts like an unordered list due the removal of a category by replacing
     *          with the last category in the array. The order does not matter however
     *          as each category has an equal chance of being selected, and categories are removed
     *          by referencind the {id} property of the struct.
     * @param   seed 32-byte hash of the random seed
     * @param   amount The number of tokens to mint
     */

    function _claimRandomItems(bytes32 seed, uint256 amount) internal {
        uint256[] memory ids = new uint256[](amount);
        uint256[] memory amounts = new uint256[](amount);

        for (uint256 i; i < amount; i++) {
            // Every category has an equal chance of being selected
            uint256 randomCategorySelector = (uint256(
                keccak256(abi.encode(seed, blockhash(block.number - 1), block.basefee, i))
            ) % (categories.length * 100)) + 1;

            uint256 id;
            for (uint256 ii; ii < categories.length; ii++) {
                if (randomCategorySelector < (ii + 1) * 100) {
                    id = _selectIdByRarity(randomCategorySelector, ii);
                    break;
                }
            }

            ids[i] = id;
            amounts[i] = 1;
        }

        inventoryContract.mintBatch(_msgSender(), ids, amounts, "");
        emit InventoryItemsClaimed(ids, amounts);
    }

    /**
     * @notice  Selects an id from the category based on rarity
     * @dev     Uses the seed and category ID to generate randomness
     * @dev     Tiers: Common (50% chance), Mid (35% chance), rare (15% chance)
     * @param   seed 32-byte hash of the random seed
     * @param   category the item category to select from
     */
    function _selectIdByRarity(uint256 seed, uint256 category) internal view returns (uint256) {
        uint256 randomIdSelector = (uint256(keccak256(abi.encode(seed, category))) % 3000) + 1;
        uint8[9] memory options = categories[category].tokenIds;

        if (randomIdSelector > 2500) {
            return options[0]; // common ( 2500 - 3000)
        } else if (randomIdSelector > 2000) {
            return options[1]; // common (2000 - 2500)
        } else if (randomIdSelector > 1500) {
            return options[2]; // common ( 1500 - 2000)
        } else if (randomIdSelector > 1150) {
            return options[3]; // mid (1150 - 1500)
        } else if (randomIdSelector > 800) {
            return options[4]; // mid (800 - 1150)
        } else if (randomIdSelector > 450) {
            return options[5]; // mid ( 450 - 800)
        } else if (randomIdSelector > 300) {
            return options[6]; // rare ( 300 - 450 )
        } else if (randomIdSelector > 150) {
            return options[7]; // rare ( 150 - 300)
        } else {
            return options[8]; // rare ( 0 - 150)
        }
    }

    // ======================================================== MODIFIERS

    /**
     * @dev Only allow contract calls from Biconomy's trusted forwarder
     */
    modifier hasValidOrigin() {
        require(
            isTrustedForwarder(msg.sender) || msg.sender == tx.origin,
            "Non-trusted forwarder contract not allowed"
        );
        _;
    }

    // ======================================================== OVERRIDES

    /**
     * @dev Override Context's _msgSender() to enable meta transactions for Biconomy
     *       relayer protocol, which allows for gasless TXs
     */
    function _msgSender()
        internal
        view
        virtual
        override(ERC2771Context, Context)
        returns (address)
    {
        return ERC2771Context._msgSender();
    }

    /**
     * @dev Override Context's _msgData(). This function is not used, but is required
     *      as an override
     */
    function _msgData()
        internal
        view
        virtual
        override(ERC2771Context, Context)
        returns (bytes calldata)
    {
        return msg.data;
    }
}
