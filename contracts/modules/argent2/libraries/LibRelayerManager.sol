// Copyright (C) 2018  Argent Labs Ltd. <https://argent.xyz>

// This program is free software: you can redistribute it and/or modify
// it under the terms of the GNU General Public License as published by
// the Free Software Foundation, either version 3 of the License, or
// (at your option) any later version.

// This program is distributed in the hope that it will be useful,
// but WITHOUT ANY WARRANTY; without even the implied warranty of
// MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
// GNU General Public License for more details.

// You should have received a copy of the GNU General Public License
// along with this program.  If not, see <http://www.gnu.org/licenses/>.

// SPDX-License-Identifier: GPL-3.0-only
pragma solidity ^0.8.0;

import "@uniswap/v2-periphery/contracts/interfaces/IUniswapV2Router01.sol";
import "@uniswap/v2-core/contracts/interfaces/IUniswapV2Pair.sol";

library LibRelayerManager {
    bytes32 constant internal DIAMOND_STORAGE_POSITION = keccak256("diamond.standard.relayermanager.storage");

    struct RelayerConfig {
        uint256 nonce;
        mapping (bytes32 => bool) executedTx;
    }

    struct RelayerManagerStorage {
        mapping (address => RelayerConfig) relayer;
        address weth;
        address uniswapV2Factory;
    }

    function diamondStorage() internal pure returns(RelayerManagerStorage storage ds) {
        bytes32 position = DIAMOND_STORAGE_POSITION;
        // solhint-disable-next-line no-inline-assembly
        assembly {
            ds.slot := position
        }
    }

    function init(address _uniswapRouter) internal {
        RelayerManagerStorage storage ds = diamondStorage();
        ds.weth = IUniswapV2Router01(_uniswapRouter).WETH();
        ds.uniswapV2Factory = IUniswapV2Router01(_uniswapRouter).factory();
    }
}