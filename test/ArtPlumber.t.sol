// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {ArtPlumber} from "../src/ArtPlumber.sol";
import {ArtPlumberRenderer} from "../src/ArtPlumberRenderer.sol";

/// @dev Minimal slice of the standard test-runner cheatcode interface,
///      declared inline to keep the repo dependency-free. sign() lets the
///      tests produce real voucher signatures for a known key.
interface Vm {
    function sign(uint256 privateKey, bytes32 digest)
        external
        pure
        returns (uint8 v, bytes32 r, bytes32 s);
    function addr(uint256 privateKey) external pure returns (address);
}

contract ArtPlumberTest {
    string constant HEAD_STICK_GEOM = "M11 0h1v4h-1z";
    string constant HELD_STICK_GEOM = "M18 11h1v3h-1z";
    string constant HEAD_SUCKER_GEOM = "M9 6h5v1h-5z";
    string constant HELD_SUCKER_GEOM = "M16 8h5v1h-5z";

    Vm constant vm = Vm(address(uint160(uint256(keccak256("hevm cheat code")))));
    uint256 constant SIGNER_KEY = uint256(keccak256("art plumber test signer"));
    uint256 constant WRONG_KEY = uint256(keccak256("not the signer"));
    address constant PAYOUT = address(0xCAFE);

    ArtPlumber nft;
    uint256 price;

    /// @dev No voucher at all: the public, pay-per-token path.
    bytes constant NO_VOUCHER = hex"";

    function setUp() public {
        nft = new ArtPlumber(vm.addr(SIGNER_KEY), PAYOUT);
        price = nft.MINT_PRICE();
    }

    /// EIP-712 voucher for `wallet`, signed by the eligibility signer.
    function voucher(address wallet) internal view returns (bytes memory) {
        return voucherFrom(SIGNER_KEY, wallet);
    }

    function voucherFrom(uint256 key, address wallet) internal view returns (bytes memory) {
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(key, nft.voucherDigest(wallet));
        return abi.encodePacked(r, s, v);
    }

    function test_MintAssignsOwnerAndSeed() public {
        // OG wallet's first token is free, so msg.value must be 0
        uint256 id = nft.mint{value: 0}(1, voucher(address(this)));
        require(id == 1, "first id should be 1");
        require(nft.ownerOf(1) == address(this), "owner");
        require(nft.seedOf(1) != bytes32(0), "seed set");
        require(nft.totalSupply() == 1, "supply");
    }

    function test_BatchMintThree() public {
        // 2 free + 1 paid in a single call
        uint256 firstId = nft.mint{value: price}(3, voucher(address(this)));
        require(firstId == 1, "batch starts at 1");
        require(nft.totalSupply() == 3, "supply");
        require(nft.mintedBy(address(this)) == 3, "wallet count");
        require(nft.freeMintedBy(address(this)) == 2, "free allowance spent");
        for (uint256 id = 1; id <= 3; id++) {
            require(nft.ownerOf(id) == address(this), "owner of batch token");
            require(nft.seedOf(id) != bytes32(0), "seed set");
        }
        // same block, same minter - ids still give every token its own roll
        require(nft.seedOf(1) != nft.seedOf(2) && nft.seedOf(2) != nft.seedOf(3), "distinct seeds");
    }

    function test_MintRejectsBadQuantity() public {
        bytes memory sig = voucher(address(this));
        try nft.mint{value: 0}(0, sig) {
            revert("quantity 0 should revert");
        } catch Error(string memory reason) {
            require(eq(reason, "BAD_QUANTITY"), "zero quantity reason");
        }
        try nft.mint{value: 19 * price}(21, sig) {
            revert("quantity 21 should revert");
        } catch Error(string memory reason) {
            require(eq(reason, "BAD_QUANTITY"), "over-MAX_PER_TX reason");
        }
    }

    function test_MintRejectsWrongPrice() public {
        try nft.mint{value: price - 1}(1, NO_VOUCHER) {
            revert("underpay should revert");
        } catch Error(string memory reason) {
            require(eq(reason, "WRONG_PRICE"), "underpay reason");
        }
        try nft.mint{value: 2 * price}(1, NO_VOUCHER) {
            revert("overpay should revert");
        } catch Error(string memory reason) {
            require(eq(reason, "WRONG_PRICE"), "overpay reason");
        }
    }

    function test_MintRejectsPaymentForAFreeToken() public {
        // an OG's first two are free: sending the public price is an overpay
        try nft.mint{value: price}(1, voucher(address(this))) {
            revert("paying for a free token should revert");
        } catch Error(string memory reason) {
            require(eq(reason, "WRONG_PRICE"), "free-token overpay reason");
        }
    }

    function test_WithdrawSendsProceedsToPayout() public {
        // 2 free + 1 paid: only the paid token contributes proceeds
        nft.mint{value: price}(3, voucher(address(this)));
        require(address(nft).balance == price, "proceeds held");
        uint256 before = PAYOUT.balance;
        nft.withdraw();
        require(address(nft).balance == 0, "contract drained");
        require(PAYOUT.balance == before + price, "payout received");
    }

    function test_WrongSignerVoucherGrantsNoFreeMint() public {
        assertNoFreeMint(voucherFrom(WRONG_KEY, address(this)), "wrong signer");
    }

    function test_BorrowedVoucherGrantsNoFreeMint() public {
        // voucher names another wallet; this contract can't claim its free mints
        assertNoFreeMint(voucher(address(0xBEEF)), "borrowed voucher");
    }

    function test_MalformedSignatureGrantsNoFreeMint() public {
        assertNoFreeMint(hex"deadbeef", "malformed signature");
    }

    function test_VoucherBoundToContractInstance() public {
        // same signer, second deployment: domain separator differs, so a
        // voucher for nft must not grant free mints on the new instance
        ArtPlumber other = new ArtPlumber(vm.addr(SIGNER_KEY), PAYOUT);
        bytes memory sigForNft = voucher(address(this));
        try other.mint{value: 0}(1, sigForNft) {
            revert("cross-contract voucher should not be free");
        } catch Error(string memory reason) {
            require(eq(reason, "WRONG_PRICE"), "wrong revert reason");
        }
        other.mint{value: price}(1, sigForNft);
        require(other.freeMintedBy(address(this)) == 0, "no free allowance consumed");
    }

    function test_ConstructorRejectsZeroSigner() public {
        try new ArtPlumber(address(0), PAYOUT) {
            revert("zero signer should revert");
        } catch Error(string memory reason) {
            require(eq(reason, "ZERO_SIGNER"), "wrong revert reason");
        }
        try new ArtPlumber(vm.addr(SIGNER_KEY), address(0)) {
            revert("zero payout should revert");
        } catch Error(string memory reason) {
            require(eq(reason, "ZERO_PAYOUT"), "wrong revert reason");
        }
    }

    function test_SeedNibblesMapToSlots() public pure {
        // nibbles (low to high): headSucker, heldSucker, headStick, heldStick,
        // suit, boots, plunger presence
        bytes32 seed = bytes32(uint256(0x0654321)); // presence nibble 0 = double
        ArtPlumberRenderer.Traits memory t = ArtPlumberRenderer.traitsOf(seed);
        require(t.headSucker == 0x1, "headSucker = nibble 0");
        require(t.heldSucker == 0x2, "heldSucker = nibble 1");
        require(t.headStick == 0x3, "headStick = nibble 2");
        require(t.heldStick == 0x4, "heldStick = nibble 3");
        require(t.suit == 0x5, "suit = nibble 4");
        require(t.boots == 0x6, "boots = nibble 5");
        require(t.headPlunger && t.heldPlunger, "nibble 6 = 0 -> double");
    }

    function test_PresenceNibbleMapping() public pure {
        // nibble 6: 0-8 double, 9-11 head only, 12-14 hand only, 15 none
        for (uint256 p = 0; p < 16; p++) {
            ArtPlumberRenderer.Traits memory t =
                ArtPlumberRenderer.traitsOf(bytes32(p << 24));
            if (p <= 8) {
                require(t.headPlunger && t.heldPlunger, "double");
            } else if (p <= 11) {
                require(t.headPlunger && !t.heldPlunger, "head only");
            } else if (p <= 14) {
                require(!t.headPlunger && t.heldPlunger, "hand only");
            } else {
                require(!t.headPlunger && !t.heldPlunger, "none");
            }
        }
    }

    function test_MatchFlags() public pure {
        // suckers match (nibbles 0,1 equal), sticks match (nibbles 2,3 equal)
        ArtPlumberRenderer.Traits memory t =
            ArtPlumberRenderer.traitsOf(bytes32(uint256(0x0217755)));
        require(ArtPlumberRenderer.suckersMatch(t), "suckers");
        require(ArtPlumberRenderer.sticksMatch(t), "sticks");
        require(!ArtPlumberRenderer.uniformMatch(t), "uniform should differ");
        require(ArtPlumberRenderer.perfectPlumber(t), "perfect");
    }

    function test_MatchesRequirePresence() public pure {
        // same matching colors, but presence nibble 15 -> no plungers shown,
        // so sucker/stick matches must not count
        ArtPlumberRenderer.Traits memory t =
            ArtPlumberRenderer.traitsOf(bytes32(uint256(0xF217755)));
        require(!ArtPlumberRenderer.suckersMatch(t), "no suckers on art");
        require(!ArtPlumberRenderer.sticksMatch(t), "no sticks on art");
        require(!ArtPlumberRenderer.perfectPlumber(t), "not perfect");
        // head only: still not a pair
        t = ArtPlumberRenderer.traitsOf(bytes32(uint256(0x9217755)));
        require(!ArtPlumberRenderer.suckersMatch(t), "single sucker");
    }

    function test_SvgContainsEachSlotColorOnce() public pure {
        // six distinct slot colors, double plungers
        ArtPlumberRenderer.Traits memory t =
            ArtPlumberRenderer.traitsOf(bytes32(uint256(0x0765432)));
        string memory s = ArtPlumberRenderer.svg(t);
        require(count(s, ArtPlumberRenderer.hexColor(t.headSucker)) == 1, "headSucker color");
        require(count(s, ArtPlumberRenderer.hexColor(t.heldSucker)) == 1, "heldSucker color");
        require(count(s, ArtPlumberRenderer.hexColor(t.headStick)) == 1, "headStick color");
        require(count(s, ArtPlumberRenderer.hexColor(t.heldStick)) == 1, "heldStick color");
        require(count(s, ArtPlumberRenderer.hexColor(t.suit)) == 1, "suit color");
        require(count(s, ArtPlumberRenderer.hexColor(t.boots)) == 1, "boots color");
        require(count(s, "<svg ") == 1 && count(s, "</svg>") == 1, "svg wrapper");
        require(count(s, HEAD_STICK_GEOM) == 1, "head stick geometry");
    }

    function test_SvgOmitsAbsentPlungers() public pure {
        // head only (nibble 6 = 9)
        string memory s =
            ArtPlumberRenderer.svg(ArtPlumberRenderer.traitsOf(bytes32(uint256(0x9765432))));
        require(count(s, HEAD_STICK_GEOM) == 1, "head stick shown");
        require(count(s, HEAD_SUCKER_GEOM) == 1, "head sucker shown");
        require(count(s, HELD_STICK_GEOM) == 0, "held stick hidden");
        require(count(s, HELD_SUCKER_GEOM) == 0, "held sucker hidden");

        // hand only (nibble 6 = 12)
        s = ArtPlumberRenderer.svg(ArtPlumberRenderer.traitsOf(bytes32(uint256(0xC765432))));
        require(count(s, HEAD_STICK_GEOM) == 0, "head stick hidden");
        require(count(s, HELD_STICK_GEOM) == 1, "held stick shown");

        // none (nibble 6 = 15): body still renders, no plunger pixels at all
        s = ArtPlumberRenderer.svg(ArtPlumberRenderer.traitsOf(bytes32(uint256(0xF765432))));
        require(count(s, HEAD_STICK_GEOM) == 0 && count(s, HELD_STICK_GEOM) == 0, "plungerless");
        require(count(s, "M9 12h5v1h-5z") == 1, "suit still drawn");
        require(count(s, "</svg>") == 1, "closed");
    }

    function test_PlungersLabel() public pure {
        require(eq(label(0x0), "Double"), "double");
        require(eq(label(0x9), "Head Only"), "head");
        require(eq(label(0xC), "Hand Only"), "hand");
        require(eq(label(0xF), "None"), "none");
    }

    function test_NoPerWalletCap() public {
        // one wallet, far past any old cap: only MAX_PER_TX bounds a single
        // call, and nothing bounds the total
        bytes memory sig = voucher(address(this));
        nft.mint{value: 18 * price}(20, sig); // 2 free + 18 paid
        nft.mint{value: 20 * price}(20, sig);
        nft.mint{value: 20 * price}(20, sig);
        require(nft.mintedBy(address(this)) == 60, "sixty minted by one wallet");
        require(nft.totalSupply() == 60, "supply");
        require(nft.freeMintedBy(address(this)) == 2, "still only two free");
        require(address(nft).balance == 58 * price, "58 paid, 2 free");
    }

    function test_MaxPerTxIsAGasGuardNotAnAllocation() public {
        // the 21st token in one call is refused, but the same wallet may
        // immediately send another full call
        bytes memory sig = voucher(address(this));
        try nft.mint{value: 19 * price}(21, sig) {
            revert("21 in one call should revert");
        } catch Error(string memory reason) {
            require(eq(reason, "BAD_QUANTITY"), "wrong revert reason");
        }
        nft.mint{value: 18 * price}(20, sig);
        nft.mint{value: 20 * price}(20, sig);
        require(nft.mintedBy(address(this)) == 40, "40 across two calls");
    }

    function test_DisclaimerOnchain() public view {
        string memory d = nft.DISCLAIMER();
        require(count(d, "no intrinsic value") == 1, "no value");
        require(count(d, "no expectation of financial return") == 1, "no return");
        require(count(d, "no team") == 1 && count(d, "no roadmap") == 1, "no team/roadmap");
        require(count(d, "entertainment purposes only") == 1, "entertainment only");
    }

    function test_TokenURIShape() public {
        uint256 id = nft.mint{value: 0}(1, voucher(address(this)));
        string memory uri = nft.tokenURI(id);
        require(startsWith(uri, "data:application/json;base64,"), "data uri prefix");
        require(bytes(uri).length > 1000, "payload present");
    }

    function test_Base64KnownVectors() public pure {
        require(eq(ArtPlumberRenderer.encode("f"), "Zg=="), "f");
        require(eq(ArtPlumberRenderer.encode("fo"), "Zm8="), "fo");
        require(eq(ArtPlumberRenderer.encode("foo"), "Zm9v"), "foo");
        require(eq(ArtPlumberRenderer.encode("foobar"), "Zm9vYmFy"), "foobar");
    }

    function test_ColorNamesCoverPalette() public pure {
        for (uint8 i = 0; i < 16; i++) {
            require(bytes(ArtPlumberRenderer.colorName(i)).length > 0, "name");
            require(bytes(ArtPlumberRenderer.hexColor(i)).length == 6, "hex");
        }
    }

    // --------------------- mint economics ----------------------

    function test_MintConstants() public view {
        require(nft.MAX_SUPPLY() == 2000, "collection size");
        require(nft.MAX_PER_TX() == 20, "gas guard per transaction");
        require(nft.FREE_ALLOWANCE() == 2, "free tokens per OG wallet");
        require(nft.MINT_PRICE() == 0.003 ether, "price per paid token");
    }

    function test_OgFirstTwoTokensAreFree() public {
        nft.mint{value: 0}(2, voucher(address(this)));
        require(nft.totalSupply() == 2, "two minted");
        require(nft.freeMintedBy(address(this)) == 2, "both counted as free");
        require(address(nft).balance == 0, "no proceeds from free mints");
    }

    function test_OgThirdTokenCostsFullPrice() public {
        bytes memory sig = voucher(address(this));
        nft.mint{value: 0}(2, sig);
        try nft.mint{value: 0}(1, sig) {
            revert("third token should not be free");
        } catch Error(string memory reason) {
            require(eq(reason, "WRONG_PRICE"), "third-token reason");
        }
        nft.mint{value: price}(1, sig);
        require(nft.mintedBy(address(this)) == 3, "three minted");
        require(nft.freeMintedBy(address(this)) == 2, "free allowance stays spent");
    }

    function test_OgPaysForEverythingPastTheFreeTwo() public {
        nft.mint{value: 18 * price}(20, voucher(address(this)));
        require(nft.mintedBy(address(this)) == 20, "twenty minted");
        require(address(nft).balance == 18 * price, "eighteen paid, two free");
    }

    function test_PublicWalletPaysForEveryToken() public {
        try nft.mint{value: 0}(1, NO_VOUCHER) {
            revert("public mint should not be free");
        } catch Error(string memory reason) {
            require(eq(reason, "WRONG_PRICE"), "public free-mint reason");
        }
        nft.mint{value: 20 * price}(20, NO_VOUCHER);
        nft.mint{value: 20 * price}(20, NO_VOUCHER);
        require(nft.mintedBy(address(this)) == 40, "no cap without a voucher either");
        require(nft.freeMintedBy(address(this)) == 0, "no free tokens without a voucher");
        require(address(nft).balance == 40 * price, "all forty paid");
    }

    function test_FreeAllowanceSurvivesEarlierPaidMints() public {
        // wallet buys first, produces a voucher later: its 2 free mints are
        // still unspent, so mintedBy alone can't stand in for freeMintedBy
        nft.mint{value: 3 * price}(3, NO_VOUCHER);
        nft.mint{value: 0}(2, voucher(address(this)));
        require(nft.mintedBy(address(this)) == 5, "five minted");
        require(nft.freeMintedBy(address(this)) == 2, "free allowance honored late");
        require(address(nft).balance == 3 * price, "only the first three paid");
    }

    function test_PriceForQuotesTheExactValue() public {
        address me = address(this);
        bytes memory sig = voucher(me);
        require(nft.priceFor(me, 2, sig) == 0, "two free");
        require(nft.priceFor(me, 5, sig) == 3 * price, "two free then three paid");
        require(nft.priceFor(me, 5, NO_VOUCHER) == 5 * price, "public pays for all");
        nft.mint{value: nft.priceFor(me, 5, sig)}(5, sig);
        require(nft.priceFor(me, 3, sig) == 3 * price, "allowance now spent");
    }

    // ------------------------- helpers -------------------------

    /// A signature that isn't a valid voucher for this wallet grants no free
    /// mint, but no longer blocks minting: the wallet just pays public price.
    function assertNoFreeMint(bytes memory sig, string memory what) internal {
        try nft.mint{value: 0}(1, sig) {
            revert(string(abi.encodePacked(what, " should not mint free")));
        } catch Error(string memory reason) {
            require(eq(reason, "WRONG_PRICE"), "expected WRONG_PRICE");
        }
        nft.mint{value: price}(1, sig);
        require(nft.freeMintedBy(address(this)) == 0, "no free allowance consumed");
        require(nft.mintedBy(address(this)) == 1, "paid mint went through");
    }

    function label(uint256 presenceNibble) internal pure returns (string memory) {
        return ArtPlumberRenderer.plungersLabel(
            ArtPlumberRenderer.traitsOf(bytes32(presenceNibble << 24))
        );
    }

    function count(string memory hay, string memory needle) internal pure returns (uint256 n) {
        bytes memory h = bytes(hay);
        bytes memory nd = bytes(needle);
        if (nd.length == 0 || h.length < nd.length) return 0;
        for (uint256 i = 0; i <= h.length - nd.length; i++) {
            bool hit = true;
            for (uint256 j = 0; j < nd.length; j++) {
                if (h[i + j] != nd[j]) {
                    hit = false;
                    break;
                }
            }
            if (hit) n++;
        }
    }

    function startsWith(string memory s, string memory prefix) internal pure returns (bool) {
        bytes memory b = bytes(s);
        bytes memory p = bytes(prefix);
        if (b.length < p.length) return false;
        for (uint256 i = 0; i < p.length; i++) {
            if (b[i] != p[i]) return false;
        }
        return true;
    }

    function eq(string memory a, string memory b) internal pure returns (bool) {
        return keccak256(bytes(a)) == keccak256(bytes(b));
    }
}
