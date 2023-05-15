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

library LibSecurityManager {
    bytes32 constant internal DIAMOND_STORAGE_POSITION = keccak256("diamond.standard.securitymanager.storage");

    struct RecoveryConfig {
        address recovery;
        uint64 executeAfter;
        uint32 guardianCount;
    }

    struct GuardianManagerConfig {
        // The time at which a guardian addition or revokation will be confirmable by the owner
        mapping (bytes32 => uint256) pending;
    }

    struct SecurityManagerStorage {
        // Wallet specific storage for recovery
        mapping (address => RecoveryConfig) recoveryConfigs;
        // Wallet specific storage for pending guardian addition/revokation
        mapping (address => GuardianManagerConfig) guardianConfigs;


        // Recovery period
        uint256 recoveryPeriod;
        // Lock period
        uint256 lockPeriod;
        // The security period to add/remove guardians
        uint256 securityPeriod;
        // The security window
        uint256 securityWindow;
    }

    function diamondStorage() internal pure returns(SecurityManagerStorage storage ds) {
        bytes32 position = DIAMOND_STORAGE_POSITION;
        // solhint-disable-next-line no-inline-assembly
        assembly {
            ds.slot := position
        }
    }
}