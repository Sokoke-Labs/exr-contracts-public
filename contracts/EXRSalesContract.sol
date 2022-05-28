// SPDX-License-Identifier: MIT
pragma solidity 0.8.9;

import "@openzeppelin/contracts/security/ReentrancyGuard.sol";
import "@openzeppelin/contracts/metatx/ERC2771Context.sol";
import "@openzeppelin/contracts/access/AccessControl.sol";
import "./interfaces/IEXRMintPass.sol";
import "./interfaces/IEXRGameAsset.sol";
import "./extensions/CouponSystem.sol";

error SalesRacecraftRedemptionNotActive();
error SalesPilotRedemptionNotActive();
error SalesExceededMintPassSupply();
error SalesAllottedClaimsExceeded();
error SalesInvalidFragmentSupply();
error SalesArrayLengthMismatch();
error SalesNonExistentFragment();
error SalesIncorrectEthAmount();
error SalesPassClaimNotActive();
error SalesInvalidStateValue();
error SalesMintpassQtyNotSet();
error SalesWithdrawalFailed();
error SalesInvalidCoupon();
error SalesRefundFailed();
error SalesZeroAddress();
error SalesNoMintPass();
error SalesInvalidQty();
error SalesReusedSeed();

/**
 * @title   Sales Contract
 * @author  RacerDev
 * @notice  This sales contract acts as an interface between the end user and the NFT
 *          contracts in the EXR ecosystem.  Users cannot mint from ERC721 and ERC1155 contracts
 *          directly, instead this contract provides controlled access to the
 *          collection Fragments for each contract.  All contract interactions with other token contracts
 *          happen via interfaces, for which the contract addresses must be set by an admin user.
 * @notice  There is no public mint or claim functions.  Claiming tokens requires the caller to pass in a signed
 *          coupon, which is used to recover the signers address on-chain to verify the validity
 *          of the Coupons.
 * @dev     This approach is designed to work with the ERC721Fragmentable extension, which allows for NFT Collections to be
 *          subdivided into smaller "Fragments", each released independently, but still part of the same contract.
 *          This is controlled via the `dedicatedFragment` variable that is set in the constructor at deploy time.
 * @dev     This contract enables gasless transactions for the end-user by replacing `msg.sender` if a trusted forwarder
 *          is the caller. This pattern allows the contract to be used with Biconomy's relayer protocol.
 */

contract EXRSalesContract is ERC2771Context, CouponSystem, ReentrancyGuard, AccessControl {
    bytes32 public constant SYS_ADMIN_ROLE = keccak256("SYS_ADMIN_ROLE");

    uint256 public constant pilotPassTokenId = 1;
    uint256 public constant racecraftPassTokenId = 2;

    // We set these in the constructor in the event the event the Sales contract is being replaced
    // for an alreaady active fragment. If not, the values will be overwritten when the fragment is created
    uint256 public pilotPassMaxSupply;
    uint256 public racecraftPassMaxSupply;

    uint8 public immutable dedicatedFragment;

    mapping(bytes32 => bool) public usedSeeds;
    struct SaleState {
        uint8 claimPilotPass;
        uint8 redeemPilot;
        uint8 redeemRacecraft;
    }

    SaleState public state;

    IEXRMintPass public mintPassContract;
    IEXRGameAsset public pilotContract;
    IEXRGameAsset public racecraftContract;

    event SalesFragmentCreated(
        uint256 supply,
        uint256 firstId,
        uint256 reservedPilots,
        uint256 reservedRacecrafts
    );
    event Airdrop(uint256 tokenId, uint256[] qtys, address[] indexed recipient);
    event RefundIssued(address indexed buyer, uint256 amount);
    event MintPassClaimed(address indexed user, uint256 qty);
    event RacecraftContractSet(address indexed racecraft);
    event MintPassContractSet(address indexed mintpass);
    event PilotStateChange(uint8 claim, uint8 redeem);
    event PilotContractSet(address indexed pilot);
    event MintPassBurned(address indexed user);
    event RacecraftStateChange(uint8 redeem);
    event AdminSignerUpdated(address signer);
    event RacecraftRedeemed();
    event BalanceWithdrawn();
    event PilotRedeemed();
    event EmergencyStop();

    /**
     * @dev     The Admin Signer is passed directly to the CouponSystem constructor where it's kept in storage.
     *          It's later used to compare against the signer recoverd from the Coupon signature.
     * @param   adminSigner The public address from the keypair whose private key signed the Coupon off-chain
     * @param   fragment    The identifier for the fragment being represented by this sales contract, which determines
     *                      which fragment of the target ERC721 contracts is used.
     */
    constructor(
        address adminSigner,
        address trustedForwarder,
        uint8 fragment,
        uint256 pilotPassMaxSupply_,
        uint256 racecraftPassMaxSupply_
    ) CouponSystem(adminSigner) ERC2771Context(trustedForwarder) {
        dedicatedFragment = fragment;
        pilotPassMaxSupply = pilotPassMaxSupply_;
        racecraftPassMaxSupply = racecraftPassMaxSupply_;
        _grantRole(DEFAULT_ADMIN_ROLE, msg.sender);
        _grantRole(SYS_ADMIN_ROLE, msg.sender);
    }

    // ======================================================== EXTERNAL | USER FUNCTIONS

    /**
     * @notice Allows a whitelisted caller to claim a Pilot Mint Pass
     * @dev    Callers are able to claim a mint pass by passing in a signed Coupon that's created off-chain.
     *         The caller's address is encoded into the Coupon, so only the intended recipient can claim a pass.
     * @dev    This is a variable-pricing function.  The cost of the claim is encoded into the Coupon and passed in as
     *         as a param. This allows different "tiers" of coupons to use the same function, eg
     *         free vs. paid. The custom price that's passed in is validated against the price included in the coupon, then
     *         compared to the amount of Eth sent in msg.value;
     * @dev    The coupon does not contain a nonce, instead the number of claims is tracked against the caller's address
     *         using the {addressToClaims} mapping. This approach allows a user to claim their allotted mint masses over
     *         multiple transactions (if desired), without the need to generate a new coupon.
     * @dev    The MintPass is minted by the contract on the user's behalf using the `MintPassContract` interface.
     * @dev    Will refund the caller if they send the incorrect amount > `msg.value`.
     * @dev    It's possible for different users to be assigned a different number of mintpass claims, the total for each user
     *         is dictated by the `allotted` parameter, which is encoded into the coupon.
     * @param  coupon signed coupon generated using caller's address, price, qty, and allotted claims
     * @param  price the custom price the caller needs to pay per pass claimed
     * @param  qty the number of passes to claim
     * @param  allotted the max number of passes the caller's address is allowed to claim (over multiple TXs if desired)
     */
    function claimPilotPass(
        Coupon calldata coupon,
        uint256 price,
        uint256 qty,
        uint256 allotted
    ) external payable nonReentrant {
        if (state.claimPilotPass == 0) revert SalesPassClaimNotActive();
        if (!pilotContract.fragmentExists(dedicatedFragment)) revert SalesNonExistentFragment();
        if (pilotPassMaxSupply == 0) revert SalesMintpassQtyNotSet();
        if (qty == 0 || allotted == 0) revert SalesInvalidQty();
        if (
            mintPassContract.tokenMintCountsByFragment(dedicatedFragment, pilotPassTokenId) + qty >
            pilotPassMaxSupply
        ) revert SalesExceededMintPassSupply();

        uint256 amountOwed = price * qty;

        address caller = _msgSender();
        uint256 paid = msg.value;

        if (paid < amountOwed) revert SalesIncorrectEthAmount();

        if (
            qty + mintPassContract.addressToPilotPassClaimsByFragment(dedicatedFragment, caller) >
            allotted
        ) revert SalesAllottedClaimsExceeded();

        bytes32 digest = keccak256(
            abi.encode(address(this), block.chainid, CouponType.MintPass, price, allotted, caller)
        );
        if (!_verifyCoupon(digest, coupon)) revert SalesInvalidCoupon();

        mintPassContract.incrementPilotPassClaimCount(caller, dedicatedFragment, qty);
        mintPassContract.mint(caller, qty, pilotPassTokenId, dedicatedFragment);
        emit MintPassClaimed(caller, qty);

        if (amountOwed < paid) {
            refundCaller(caller, paid - amountOwed);
        }
    }

    /**
     * @notice  The caller can claim an EXRGameAsset token in exchange for burning their Pilot MintPass
     * @dev     Checks the balance of Mint Pass tokens for caller's address, burns the mint pass via
     *          the MintPass contract interface, and mints a Pilot to the callers address via the
     *          EXRGameAsset contract Interface
     * @dev     The EXRGameAsset token will be minted for the fragment of the collection determined by
     *          `dedicatedFragment`, which is set at deploy time.  Only tokens for this fragment can be minted
     *          using this Fragment Sales Contract.
     * @dev     At the time of writing, the Moonbeam network has no method of generating unpredictable randomness
     *          such as Chainlink's VRF.  For this reason, a random seed, generated off-chain, is supplied to the
     *          redeem method to allow for random token assignment of the pilot IDs.
     * @dev     We need to check {pilotPasssMaxSupply} in the event the sales contract was replaced for an existing fragment.
     * @param   seed Random seed generated off-chain
     * @param   coupon The coupon encoding the random seed signed by the admin's private key
     */
    function redeemPilot(bytes32 seed, Coupon calldata coupon)
        external
        nonReentrant
        hasValidOrigin
    {
        if (state.redeemPilot == 0) revert SalesPilotRedemptionNotActive();
        if (!pilotContract.fragmentExists(dedicatedFragment)) revert SalesNonExistentFragment();
        if (pilotPassMaxSupply == 0) revert SalesMintpassQtyNotSet();
        if (usedSeeds[seed]) revert SalesReusedSeed();

        usedSeeds[seed] = true;

        address caller = _msgSender();
        if (mintPassContract.balanceOf(caller, pilotPassTokenId) == 0) revert SalesNoMintPass();

        bytes32 digest = keccak256(
            abi.encode(address(this), block.chainid, CouponType.Pilot, seed, caller)
        );
        if (!_verifyCoupon(digest, coupon)) revert SalesInvalidCoupon();

        mintPassContract.burnToRedeemPilot(caller, dedicatedFragment);
        emit MintPassBurned(caller);

        pilotContract.mint(caller, 1, dedicatedFragment, seed);
        emit PilotRedeemed();
    }

    /**
     * @notice  Allows the holder of a Racecraft Mint Pass to exchange it for a Racecraft Token
     * @dev     There is no VRF available, so the caller includes a verifiably random seed generated
     *          off-chain in the calldata
     * @param   seed 32-byte hash of the random seed
     * @param   coupon Coupon containing the random seed and RandomSeed enum
     */
    function redeemRacecraft(bytes32 seed, Coupon calldata coupon)
        external
        nonReentrant
        hasValidOrigin
    {
        if (state.redeemRacecraft == 0) revert SalesRacecraftRedemptionNotActive();
        if (!racecraftContract.fragmentExists(dedicatedFragment))
            revert SalesNonExistentFragment();
        if (racecraftPassMaxSupply == 0) revert SalesMintpassQtyNotSet();
        if (usedSeeds[seed]) revert SalesReusedSeed();

        usedSeeds[seed] = true;

        address caller = _msgSender();
        if (mintPassContract.balanceOf(caller, racecraftPassTokenId) == 0)
            revert SalesNoMintPass();

        bytes32 digest = keccak256(
            abi.encode(address(this), block.chainid, CouponType.Racecraft, seed, caller)
        );
        if (!_verifyCoupon(digest, coupon)) revert SalesInvalidCoupon();

        mintPassContract.authorizedBurn(caller, racecraftPassTokenId);
        racecraftContract.mint(caller, 1, dedicatedFragment, seed);
        emit RacecraftRedeemed();
    }

    // ======================================================== EXTERNAL | OWNER FUNCTIONS

    /**
     *  @notice Allows an admin to set the address for the mint pass contract interface
     *  @dev    Sets the public address variable for visibility only, it's not actually used
     *  @param  contractAddress The address for the external EXRMintPass ERC1155 contract
     */
    function setMintPassContract(address contractAddress) external onlyRole(SYS_ADMIN_ROLE) {
        if (contractAddress == address(0)) revert SalesZeroAddress();
        mintPassContract = IEXRMintPass(contractAddress);
        emit MintPassContractSet(contractAddress);
    }

    /**
     *   @notice Allows an admin to set the address for the IEXRGameAsset contract interface
     *   @dev    Sets the public address variable for visibility only, it's not actually used
     *   @param  contractAddress The address for the external IEXRGameAsset ERC721 contract
     */
    function setPilotContract(address contractAddress) external onlyRole(SYS_ADMIN_ROLE) {
        if (contractAddress == address(0)) revert SalesZeroAddress();
        pilotContract = IEXRGameAsset(contractAddress);
        emit PilotContractSet(contractAddress);
    }

    /**
     *   @notice Allows an admin to set the address for the IEXRGameAsset contract interface
     *   @dev    Sets the public address variable for visibility only, it's not actually used
     *   @param  contractAddress The address for the external IEXRGameAsset ERC721 contract
     */
    function setRacecraftContract(address contractAddress) external onlyRole(SYS_ADMIN_ROLE) {
        if (contractAddress == address(0)) revert SalesZeroAddress();
        racecraftContract = IEXRGameAsset(contractAddress);
        emit RacecraftContractSet(contractAddress);
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
     * @notice Used to toggle the claim state between true/false, which controls whether callers are able to claim a mint pass
     * @dev    Should generally be enabled using flashbots to avoid backrunning, though may not be an issue with no "public sale"
     */
    function setPilotState(uint8 passClaim, uint8 redemption) external onlyRole(SYS_ADMIN_ROLE) {
        if (passClaim > 1 || redemption > 1) revert SalesInvalidStateValue();
        state.claimPilotPass = passClaim;
        state.redeemPilot = redemption;
        emit PilotStateChange(passClaim, redemption);
    }

    /**
     * @notice Used to toggle the claim state between true/false, which controls whether callers are able to burn their mint passes
     * @dev Should generally be enabled using flashbots to avoid backrunning, though may not be an issue with no "public sale"
     */

    function setRacecraftState(uint8 redemption) external onlyRole(SYS_ADMIN_ROLE) {
        if (redemption > 1) revert SalesInvalidStateValue();
        state.redeemRacecraft = redemption;
        emit RacecraftStateChange(redemption);
    }

    /**
     * @notice  Allows an Admin user to airdrop Mintpass Tokens to known addresses
     * @param   tokenId the ID of the Mintpass token to be airdropped
     * @param   qtys array containting the number of passes to mint for the address
     *              at the corresponding index in the `recipients` array
     * @param   recipients array of addresses to mint tokens to
     */
    function airdropMintpass(
        uint256 tokenId,
        uint256[] calldata qtys,
        address[] calldata recipients
    ) external onlyRole(SYS_ADMIN_ROLE) {
        if (qtys.length != recipients.length) revert SalesArrayLengthMismatch();
        if (pilotPassMaxSupply == 0) revert SalesMintpassQtyNotSet();

        uint256 count = qtys.length;
        uint256 totalQty;
        for (uint256 i; i < count; i++) {
            totalQty += qtys[i];
        }
        if (
            mintPassContract.tokenMintCountsByFragment(dedicatedFragment, tokenId) + totalQty >
            pilotPassMaxSupply
        ) revert SalesExceededMintPassSupply();

        for (uint256 i; i < count; i++) {
            mintPassContract.mint(recipients[i], qtys[i], tokenId, dedicatedFragment);
        }
        emit Airdrop(tokenId, qtys, recipients);
    }

    /**
     * @notice   Allows the contract owner to create fragments of the same size simultaneously for the Pilot
     *           and Racecraft collections.
     * @dev      There may exist some scenarios where the number of reserved pilots and
     *           racecraft might differ for a given fragment. For this reason, separate reserve amounts
     *           can be supplied.
     * @param    fragmentSupply     The number of total tokens in the fragment.
     * @param    firstId            The first token ID in the fragment
     * @param    reservedPilots     The number of reserved tokens in the Pilot fragment.
     * @param    reservedRacecrafts The number of reserved tokens in the Racecraft fragment.
     */
    function createFragments(
        uint64 fragmentSupply,
        uint64 firstId,
        uint64 reservedPilots,
        uint64 reservedRacecrafts
    ) external onlyRole(SYS_ADMIN_ROLE) {
        if (fragmentSupply <= reservedPilots || fragmentSupply <= reservedRacecrafts)
            revert SalesInvalidFragmentSupply();
        pilotPassMaxSupply = fragmentSupply - reservedPilots;
        racecraftPassMaxSupply = fragmentSupply - reservedRacecrafts;
        pilotContract.createFragment(dedicatedFragment, fragmentSupply, firstId, reservedPilots);
        racecraftContract.createFragment(
            dedicatedFragment,
            fragmentSupply,
            firstId,
            reservedRacecrafts
        );
        emit SalesFragmentCreated(fragmentSupply, firstId, reservedPilots, reservedRacecrafts);
    }

    /**
     * @notice  Prevents any user-facing function from being called
     * @dev     Behaves similarly to Pausable
     */
    function emergencyStop() external onlyRole(SYS_ADMIN_ROLE) {
        state.claimPilotPass = 0;
        state.redeemPilot = 0;
        state.redeemRacecraft = 0;
        emit EmergencyStop();
    }

    /**
     * @notice  Withdraw the Eth stored in the contract to the owner's address.
     * @dev     User transfer() in favor of call() for the withdrawal as it's only to the owner's address.
     */
    function withdrawBalance() external onlyRole(SYS_ADMIN_ROLE) {
        (bool success, ) = msg.sender.call{value: address(this).balance}("");
        if (!success) revert SalesWithdrawalFailed();
        emit BalanceWithdrawn();
    }

    // ======================================================== PRIVATE

    /**
     * @notice  Used to refund a caller who overpays for their mintpass.
     * @dev     Use `call` over `transfer`
     * @param   buyer The address/account to send the refund to
     * @param   amount The value (in wei) to refund to the caller
     * */
    function refundCaller(address buyer, uint256 amount) private {
        (bool success, ) = buyer.call{value: amount}("");
        if (!success) revert SalesRefundFailed();
        emit RefundIssued(buyer, amount);
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
