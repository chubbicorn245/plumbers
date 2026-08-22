// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {ArtPlumber} from "../src/ArtPlumber.sol";
import {ArtPlumberRenderer} from "../src/ArtPlumberRenderer.sol";

contract ArtPlumberTest {
    string constant HEAD_STICK_GEOM = "M11 0h1v4h-1z";
    string constant HELD_STICK_GEOM = "M18 11h1v3h-1z";
    string constant HEAD_SUCKER_GEOM = "M9 6h5v1h-5z";
    string constant HELD_SUCKER_GEOM = "M16 8h5v1h-5z";

    ArtPlumber nft;

    function setUp() public {
        nft = new ArtPlumber();
    }

    function test_MintAssignsOwnerAndSeed() public {
        uint256 id = nft.mint();
        require(id == 1, "first id should be 1");
        require(nft.ownerOf(1) == address(this), "owner");
        require(nft.seedOf(1) != bytes32(0), "seed set");
        require(nft.totalSupply() == 1, "supply");
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

    function test_WalletLimit() public {
        nft.mint();
        nft.mint();
        nft.mint();
        require(nft.mintedBy(address(this)) == 3, "three minted");
        try nft.mint() {
            revert("4th mint should revert");
        } catch Error(string memory reason) {
            require(eq(reason, "WALLET_LIMIT"), "wrong revert reason");
        }
        require(nft.totalSupply() == 3, "supply unchanged by failed mint");
    }

    function test_TokenURIShape() public {
        uint256 id = nft.mint();
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

    // ------------------------- helpers -------------------------

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
