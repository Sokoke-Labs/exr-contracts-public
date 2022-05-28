// SPDX-License-Identifier: MIT
pragma solidity 0.8.9;

interface IEXRMintPass {
    function balanceOf(address account, uint256 id) external view returns (uint256);

    function totalSupply(uint256 id) external view returns (uint256);

    function mint(
        address recipient,
        uint256 qty,
        uint256 tokenId,
        uint256 fragment
    ) external;

    function burnToRedeemPilot(address account, uint256 fragment) external;

    function authorizedBurn(address account, uint256 tokenId) external;

    function tokenMintCountsByFragment(uint256 fragment, uint256 tokenId)
        external
        view
        returns (uint256);

    function addressToPilotPassClaimsByFragment(uint256 fragment, address caller)
        external
        view
        returns (uint256);

    function incrementPilotPassClaimCount(
        address caller,
        uint256 fragment,
        uint256 qty
    ) external;
}
