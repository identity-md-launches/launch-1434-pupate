// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import {Cocoon} from "../../src/Cocoon.sol";

/// @dev Test-only auction taker that calls back. When Cocoon pays it (the excess of a harvest take, or
/// the ETH lot of the IMD auction), it tries to open the same kind of auction again from inside that
/// payment, while whatever Cocoon was about to hand over may still be in Cocoon's balance. What
/// Cocoon answered is recorded; the take itself goes through either way, and the test judges the
/// books afterwards.
contract ReopeningTaker {
    Cocoon public immutable cocoon;
    address public token; // the harvest token being taken; address(0) for the IMD auction
    bool public armed;
    bool public reopened;
    bytes public refusal;

    constructor(Cocoon cocoon_) {
        cocoon = cocoon_;
    }

    /// @dev Takes a harvest auction, sending `value` along, and reopens it from the refund.
    function takeHarvest(address token_, uint256 value) external {
        token = token_;
        _reset();
        cocoon.takeAuction{value: value}(token_);
        armed = false;
    }

    /// @dev Takes the IMD auction (the IMD must already be approved) and reopens it from the payout.
    function takeImd() external {
        token = address(0);
        _reset();
        cocoon.takeImdAuction();
        armed = false;
    }

    function _reset() private {
        armed = true;
        reopened = false;
        refusal = "";
    }

    receive() external payable {
        if (!armed) return;
        armed = false;
        if (token == address(0)) {
            try cocoon.startImdAuction() {
                reopened = true;
            } catch (bytes memory reason) {
                refusal = reason;
            }
        } else {
            try cocoon.startAuction(token) {
                reopened = true;
            } catch (bytes memory reason) {
                refusal = reason;
            }
        }
    }
}
