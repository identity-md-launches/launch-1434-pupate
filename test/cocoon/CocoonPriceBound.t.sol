// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import {ItemType, OrderType} from "seaport-types/src/lib/ConsiderationEnums.sol";
import {
    AdvancedOrder,
    ConsiderationItem,
    CriteriaResolver,
    OfferItem,
    Order,
    OrderParameters
} from "seaport-types/src/lib/ConsiderationStructs.sol";
import {Cocoon} from "../../src/Cocoon.sol";
import {CocoonFixture} from "../utils/CocoonFixture.sol";

/// @dev The lower bound on a purchase price binds what the vault actually pays, not the order's
/// ceiling. Seaport charges the current amount of a rising or falling listing, so a bound on the
/// larger of the two amounts would let a listing that falls to a wei be bought for about nothing: a
/// cost of a wei on the books, a tilted mode, and a seat bought back from the vault's own listing
/// for about as little. Found by the independent audit of the vault before the third launch.
contract CocoonPriceBoundTest is CocoonFixture {
    uint256 constant CHEAP = 8;
    CriteriaResolver[] internal noResolvers;

    function setUp() public override {
        super.setUp();
        _endLaunch();
        collection.mint(seller, CHEAP);
        vm.prank(seller);
        collection.setApprovalForAll(address(seaport), true);
        _setFloor(2.8 ether);
        _deposit(10 ether);
    }

    function _order(
        address offerer,
        uint256 tokenId,
        uint256 startAmount,
        uint256 endAmount,
        uint256 startTime,
        uint256 endTime,
        uint256 salt
    ) internal view returns (OrderParameters memory p) {
        OfferItem[] memory offer = new OfferItem[](1);
        offer[0] = OfferItem(ItemType.ERC721, address(collection), tokenId, 1, 1);
        ConsiderationItem[] memory c = new ConsiderationItem[](1);
        c[0] = ConsiderationItem(ItemType.NATIVE, address(0), 0, startAmount, endAmount, payable(offerer));
        p = OrderParameters(
            offerer,
            address(0),
            offer,
            c,
            OrderType.FULL_OPEN,
            startTime,
            endTime,
            bytes32(0),
            salt,
            bytes32(0),
            1
        );
    }

    function _validateAs(address offerer, OrderParameters memory p) internal {
        Order[] memory o = new Order[](1);
        o[0] = Order(p, "");
        vm.prank(offerer);
        seaport.validate(o);
    }

    function test_descendingListingNearItsEndIsRefused() public {
        OrderParameters memory cheap =
            _order(seller, CHEAP, 2.94 ether, 1, block.timestamp - (365 days - 1), block.timestamp + 1, 2);
        _validateAs(seller, cheap);
        (uint256 potBefore,,,) = _pots();
        vm.prank(seller);
        vm.expectRevert(Cocoon.BadOrder.selector);
        cocoon.buySeat(AdvancedOrder(cheap, 1, 1, "", ""), noResolvers);
        assertEq(collection.ownerOf(CHEAP), seller);
        assertEq(cocoon.seatPot(), potBefore);
        _assertBalanceIdentity();
    }

    function test_ascendingListingInItsFirstSecondIsRefused() public {
        OrderParameters memory cheap =
            _order(seller, CHEAP, 1, 2.94 ether, block.timestamp, block.timestamp + 365 days, 3);
        _validateAs(seller, cheap);
        vm.prank(seller);
        vm.expectRevert(Cocoon.BadOrder.selector);
        cocoon.buySeat(AdvancedOrder(cheap, 1, 1, "", ""), noResolvers);
    }

    function test_descendingListingStillAboveHalfTheFloorIsBought() public {
        // Falls from 2.94 to 1.5 ETH over 7 days; bought half way, at about 2.22 ETH.
        OrderParameters memory p = _order(
            seller, CHEAP, 2.94 ether, 1.5 ether, block.timestamp - 3.5 days, block.timestamp + 3.5 days, 5
        );
        _validateAs(seller, p);
        vm.prank(keeper);
        cocoon.buySeat(AdvancedOrder(p, 1, 1, "", ""), noResolvers);
        (uint128 cost,,,,, bool held,) = cocoon.seats(CHEAP);
        assertTrue(held);
        assertGt(cost, 1.4 ether);
        assertLt(cost, 2.94 ether);
    }

    function test_flatListingAtHalfTheFloorIsBought() public {
        OrderParameters memory half =
            _order(seller, CHEAP, 1.4 ether, 1.4 ether, block.timestamp, block.timestamp + 7 days, 4);
        _validateAs(seller, half);
        vm.prank(keeper);
        cocoon.buySeat(AdvancedOrder(half, 1, 1, "", ""), noResolvers);
        (uint128 cost,,,,,,) = cocoon.seats(CHEAP);
        assertEq(cost, 1.4 ether);
    }

    function test_flatListingJustUnderHalfTheFloorIsRefused() public {
        OrderParameters memory under =
            _order(seller, CHEAP, 1.4 ether - 1, 1.4 ether - 1, block.timestamp, block.timestamp + 7 days, 6);
        _validateAs(seller, under);
        vm.prank(keeper);
        vm.expectRevert(Cocoon.BadOrder.selector);
        cocoon.buySeat(AdvancedOrder(under, 1, 1, "", ""), noResolvers);
    }
}
