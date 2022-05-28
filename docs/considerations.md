# Considerations

Table of Contents:

1. [Gas Fees](#gas-fees)
1. [Random Number Generation](#random-number-generation)
1. [Launch Strategy](#launch-strategy)
1. [On-chain Mechanics](#on-chain-mechanics)

# Gas Fees

One of the primary decisions for selecting the Moonbeam network for the project is the user-friendly gas fees. At the time of writing, $GLMR (Moonbeam’s native token) sits at `$2.79`. While it’s a given that extreme volatility is a part of crypto, this example is for illustrative purposes only and assumes the project will launch in the near future (< 2months from the time of writing).

A fictional transaction on Moonbeam, such as minting an ERC721 token that requires `150k Gas`, at an average price of `150 Gwei` ( `0.00000015 GLMR` ), would incur a transaction fee of `0.0225 GLMR`, which at the given price of GLMR would total `$0.06`.

Given the relatively low transaction fees, we’ve intentionally favoured code readability over small gas optimizations that might make the code more difficult to follow. This includes the use of additional events that might otherwise be considered a waste of gas, but will provide additional metrics and allow for more in-depth analytics of on-chain data.

Despite the relatively low-cost transaction fees, the project will make use of Biconomy’s relayer protocol to enable low-friction gasless transactions for users. This means that the transaction costs will be shifted to the project owner, which has been deemed an acceptable tradeoff for providing users a seamless minting and in-game experience.

# Random Number Generation

At the time of the project’s development, there is no on-chain random number generator (such as Chainlink’s VRF) available. We did not want to settle for a purely pseudorandom onchain approach, such as the commonly utilised variations of casting a `keccak` hash of block-dependent data to a `uint256`. For example:

```
uint256 randomNum = uint256(keccak256(abi.encode(msg.sender, block.number - 1))) % 1000;
```

Given that we don't have something like VRF available, our solution adds an extra layer of security against manipulation by miners by providing a secure random seed generated off-chain. An example usage is during the redemption of inventory items via the `EXRInventoryController`’s `burnToRedeemInventory` function. The function signature is as follows:

```
 function burnToRedeemInventoryItems(
       bytes32 seed,
       uint256 qty,
       Coupon calldata coupon
   )
```

he 32-byte seed is created using the keccak hash of a random integer generated off-chain. This hash, along with the number of items to be redeemed (`qty`) are encoded in a `Coupon` that's signed using an Admin private key. The validity of the random seed is checked by the `_verifyCoupon` function, that uses `ecrecover` to compare the signer's public key against the one set in the contract's constructor during deployment. If the seed is valid, it's used as a seed for the randomness when selecting which Inventory Item to mint.

```
uint256 randomNum = (uint256(keccak256(abi.encode(msg.sender, block.number - 1, seed, i))) % 1000) + 1;
```

While more secure than relaying on block-data alone, it is not a perfect solution, and the contract can be replaced when a solution such as VRF becomes available.

# Launch Strategy

Launching an successful NFT collection is challenging. Every major NFT drop, regardless of the size of the team and its experience, usually experiences one or more issues at the time of launch. Given that we, or anyone for that matter, has little-to-no experience launching an NFT project on Moonbeam, focusing on the release of one collection at a time. This affords our team the ability to focus on one task at a time, giving us the highest chance of success and creating a smooth experience for our collectors. This is important from both an operational and reputational standpoint.

Team reputation and the ability to deliver on roadmap items are an important aspect of a collector's assessment of an NFT project and its prospects. We feel that by creating multiple experiences, spread out over time, as opposed to one large launch (all NFTs + game etc), we’ll build trust and a growing sense of excitement over the brand and the product. This forms part of the project's marketing plan - using mintpasses that are exchanged for collection items as a way to build excitement.

The use of the burn-to-exchange mechanic for the mintpasses introduces an additional challenge for the release lifecycle. A user may choose to hold their mintpass through the claim period and after the reveal. This gives the remaining pass holders an unfair advantage, in that they're able to identify which tokens are yet to be minted, and in what order, and may attempt to exploit this by frontrunning transactions, or conspiring with miners. To combat this, the `ERC721Fragmentable` specification introduces random token ID assignment at mint time. This strategy, combined with the RNG approach mentioned above, makes it practically impossible to for a pass holder to minted a specific token ID.

Even without NFTs, launching a game is hard. We’ve benefited immensely from our closed Alpha testing phase - keeping a small group of engaged users who can offer constructive feedback and test new features. By launching the NFTs prior to the game, we give ourselves the opportunity to establish a relationship with our community and have them invested in the brand and the project by the time the beta version of the game launches. In addition, it's highlighted the importance of controlling the size of the user base. This is the motivation for the `ERC721Fragmentable` extension's design. Instead of flooding the market with NFTs at the outset, it allows for the introduction of new game assets, and thus new players, into the ecosystem in a controlled and sustainable manner over time.

In addition, by only having one `payable` contract call, minting the initial Pilot Mintpass that gives access to all the other mintpasses and therefore NFTs, it allows every subsequent phase of the launch to utilize Biconomy's relayer protocol to provide the users with a gass-fee-free experience.

# On-chain Mechanics

At the time of launch, the game will not make use of any on-chain game mechanics. NFT metadata will be stored off-chain using the IPFS network. The game itself is still in the early stages of its development and as such the NFT smart contracts cannot contain features that are yet to be developed. For the time being, game asset attributes (such as `Speed`, `Agility`, `Focus` etc) will form part of the off-chain metadata. Ultimately, the goal will be to bring the metadata onchain, giving users the ability to modify, or upgrade, the NFTs that they own. Because these features have not been developed yet, the `ERC721Fragmentable` extension, which the `EXRGameAssetERC721` contract inherits from, includes a feature allowing the contract owner to assign a contract that will serve has a on-chain renderer.

```
    function setRenderer(uint256 fragmentNumber, address renderContract)
        external
        onlyRole(SYS_ADMIN_ROLE)
    {
        if (fragments[fragmentNumber].status == 0) revert FragmentInvalid();
        if (fragments[fragmentNumber].locked == 1) revert FragmentLocked();
        fragments[fragmentNumber].renderer = IRenderer(renderContract);
        emit FragmentExternalRendererSet(fragmentNumber, renderContract);
    }
```

Each Fragment of the collection (this topic is explored and explained in detail in the [docs/erc721fragmentable_spec.md](./erc721fragmentable_spec.md) section of the documentation) can be assigned its own rendering contract. The `tokenURI` for each token is fetched via an interface to the rendering contract, where all of the asset's data can be stored on-chain. External functions in the rendering contracts may provide users the ability to upgrade, or change, their token's metadata, providing game conditions allow for it. The `ERC721Fragmentable`'s `_fragmentTokenURI` function, shown below, will return the URI from the renderer only if it has been set:

```

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
                : prerevealURI;
    }
```
