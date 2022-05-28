// SPDX-License-Identifier: MIT
pragma solidity 0.8.9;

error InvalidSignature();

/**
 * @title   Coupon System
 * @author  RacerDev
 * @notice  Helper contract for verifying signed coupons using `ecrecover` to match the coupon signer
 *          to the `_adminSigner` variable set during construction.
 * @dev     The Coupon struct represents a decoded signature that was created off-chain
 */
contract CouponSystem {
    address internal _adminSigner;

    enum CouponType {
        MintPass,
        Pilot,
        Racecraft,
        Inventory,
        Reward
    }

    struct Coupon {
        bytes32 r;
        bytes32 s;
        uint8 v;
    }

    constructor(address signer) {
        _adminSigner = signer;
    }

    /**
     * @dev     Admin can replace the admin signer address in the event the private key is compromised
     * @param   newSigner The public key (address) of the new signer keypair
     */
    function _replaceSigner(address newSigner) internal {
        _adminSigner = newSigner;
    }

    /**
     * @dev     Accepts an already hashed set of data
     * @param   digest The hash of the abi.encoded coupon data
     * @param   coupon The decoded r,s,v components of the signature
     * @return  Whether the recovered signer address matches the `_adminSigner`
     */
    function _verifyCoupon(bytes32 digest, Coupon calldata coupon) internal view returns (bool) {
        address signer = ecrecover(digest, coupon.v, coupon.r, coupon.s);
        if (signer == address(0)) revert InvalidSignature();
        return signer == _adminSigner;
    }
}
