// Copyright (C) 2021  Argent Labs Ltd. <https://argent.xyz>

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

import "argent-trustlists/contracts/interfaces/IAuthoriser.sol";
import "../../../wallet/IWallet.sol";
import "../../../infrastructure/IModuleRegistry.sol";
import "../../../infrastructure/storage/IGuardianStorage.sol";
import "../../../infrastructure/storage/ITransferStorage.sol";

library LibBaseModule {

    bytes32 constant internal DIAMOND_STORAGE_POSITION = keccak256("diamond.standard.LibBaseModule");

    enum OwnerSignature {
        Anyone,             // Anyone
        Required,           // Owner required
        Optional,           // Owner and/or guardians
        Disallowed,         // Guardians only
        Session             // Session only
    }

    struct Session {
        address key;
        uint64 expires;
    }

    struct Lock {
        // the lock's release timestamp
        uint64 release;
        // the signature of the method that set the last lock
        bytes4 locker;
    }

    struct BaseModuleStorage {
        // The module registry
        IModuleRegistry registry;
        // The guardians storage
        IGuardianStorage guardianStorage;
        // The trusted contacts storage
        ITransferStorage userWhitelist;
        // The authoriser
        IAuthoriser authoriser;
        // Maps wallet to session
        mapping (address => Session) sessions;
        // Wallet specific lock storage
        mapping (address => Lock) locks;

    }

    function diamondStorage() internal pure returns(BaseModuleStorage storage ds) {
        bytes32 position = DIAMOND_STORAGE_POSITION;
        // solhint-disable-next-line no-inline-assembly
        assembly {
            ds.slot := position
        }
    }

    function _clearSession(address _wallet) internal {
        BaseModuleStorage storage s = diamondStorage();
        delete s.sessions[_wallet];
    }

    function _getLocks() internal view returns (mapping (address => Lock) storage) {
        BaseModuleStorage storage s = diamondStorage();
        return s.locks;
    }

    function _isLocked(address _wallet) internal view returns (bool) {
        BaseModuleStorage storage s = diamondStorage();
        return s.locks[_wallet].release > uint64(block.timestamp);
    }

    function _getLock(address _wallet) internal view returns (Lock storage) {
        BaseModuleStorage storage s = diamondStorage();
        return s.locks[_wallet];
    }

    function _setLock(address _wallet, uint64 _releaseAfter, bytes4 _locker) internal {
        BaseModuleStorage storage s = diamondStorage();
        s.locks[_wallet] = Lock(_releaseAfter, _locker);
    }

    function _getSessions() internal view returns (mapping (address => Session) storage) {
        BaseModuleStorage storage s = diamondStorage();
        return s.sessions;
    }

    function _getSession(address _wallet) internal view returns (Session storage) {
        BaseModuleStorage storage s = diamondStorage();
        return s.sessions[_wallet];
    }

    function _setSession(address _wallet, address _sessionUser, uint64 expiry) internal {
        BaseModuleStorage storage s = diamondStorage();
        s.sessions[_wallet] = Session(_sessionUser, expiry);
    }

    function _registry() internal view returns (IModuleRegistry) {
        BaseModuleStorage storage s = diamondStorage();
        return s.registry;
    }

    function _guardianStorage() internal view returns (IGuardianStorage) {
        BaseModuleStorage storage s = diamondStorage();
        return s.guardianStorage;
    }

    function _userWhitelist() internal view returns (ITransferStorage) {
        BaseModuleStorage storage s = diamondStorage();
        return s.userWhitelist;
    }

    function _authoriser() internal view returns (IAuthoriser) {
        BaseModuleStorage storage s = diamondStorage();
        return s.authoriser;
    }
}