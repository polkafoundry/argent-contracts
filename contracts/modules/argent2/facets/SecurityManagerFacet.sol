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

import "@openzeppelin/contracts/utils/math/SafeCast.sol";
import "./BaseFacet.sol";
import "../../common/Utils.sol";
import "../libraries/LibBaseModule.sol";
import "../libraries/LibSecurityManager.sol";

contract SecurityManagerFacet is BaseFacet {
    // *************** Events *************************** //

    event RecoveryExecuted(address indexed wallet, address indexed _recovery, uint64 executeAfter);
    event RecoveryFinalized(address indexed wallet, address indexed _recovery);
    event RecoveryCanceled(address indexed wallet, address indexed _recovery);
    event OwnershipTransfered(address indexed wallet, address indexed _newOwner);
    event Locked(address indexed wallet, uint64 releaseAfter);
    event Unlocked(address indexed wallet);
    event GuardianAdditionRequested(address indexed wallet, address indexed guardian, uint256 executeAfter);
    event GuardianRevokationRequested(address indexed wallet, address indexed guardian, uint256 executeAfter);
    event GuardianAdditionCancelled(address indexed wallet, address indexed guardian);
    event GuardianRevokationCancelled(address indexed wallet, address indexed guardian);
    event GuardianAdded(address indexed wallet, address indexed guardian);
    event GuardianRevoked(address indexed wallet, address indexed guardian);
    event WalletSecurityEnabled(address indexed wallet);
    event WalletSecurityDisablingRequested(address indexed wallet, uint256 executeAfter);
    event WalletSecurityDisablingCancelled(address indexed wallet);
    event WalletSecurityDisabled(address indexed wallet);
    // *************** Modifiers ************************ //

    /**
     * @notice Throws if there is no ongoing recovery procedure.
     */
    modifier onlyWhenRecovery(address _wallet) {
        LibSecurityManager.SecurityManagerStorage storage ds = LibSecurityManager.diamondStorage();
        require(ds.recoveryConfigs[_wallet].executeAfter > 0, "SM: no ongoing recovery");
        _;
    }

    /**
     * @notice Throws if there is an ongoing recovery procedure.
     */
    modifier notWhenRecovery(address _wallet) {
        LibSecurityManager.SecurityManagerStorage storage ds = LibSecurityManager.diamondStorage();
        require(ds.recoveryConfigs[_wallet].executeAfter == 0, "SM: ongoing recovery");
        _;
    }

    /**
     * @notice Throws if the caller is not a guardian for the wallet or the module itself.
     */
    modifier onlyGuardianOrSelf(address _wallet) {
        require(_isSelf(msg.sender) || isGuardian(_wallet, msg.sender), "SM: must be guardian/self");
        _;
    }

    // *************** External functions ************************ //

    // *************** Recovery functions ************************ //

    /**
     * @notice Lets the guardians start the execution of the recovery procedure.
     * Once triggered the recovery is pending for the security period before it can be finalised.
     * Must be confirmed by N guardians, where N = ceil(Nb Guardians / 2).
     * @param _wallet The target wallet.
     * @param _recovery The address to which ownership should be transferred.
     */
    function executeRecovery(address _wallet, address _recovery) external onlySelf() notWhenRecovery(_wallet) onlyWhenSecurityEnabled(_wallet) {
        validateNewOwner(_wallet, _recovery);
        LibSecurityManager.SecurityManagerStorage storage ds = LibSecurityManager.diamondStorage();
        uint64 executeAfter = uint64(block.timestamp + ds.recoveryPeriod);
        ds.recoveryConfigs[_wallet] = LibSecurityManager.RecoveryConfig(
            _recovery,
            executeAfter,
            uint32(LibBaseModule._guardianStorage().guardianCount(_wallet))
        );
        _setLock(_wallet, block.timestamp + ds.lockPeriod, SecurityManagerFacet.executeRecovery.selector);
        emit RecoveryExecuted(_wallet, _recovery, executeAfter);
    }

    /**
     * @notice Finalizes an ongoing recovery procedure if the security period is over.
     * The method is public and callable by anyone to enable orchestration.
     * @param _wallet The target wallet.
     */
    function finalizeRecovery(address _wallet) external onlyWhenRecovery(_wallet) onlyWhenSecurityEnabled(_wallet) {
        LibSecurityManager.SecurityManagerStorage storage ds = LibSecurityManager.diamondStorage();
        LibSecurityManager.RecoveryConfig storage config = ds.recoveryConfigs[_wallet];
        require(uint64(block.timestamp) > config.executeAfter, "SM: ongoing recovery period");
        address recoveryOwner = config.recovery;
        delete ds.recoveryConfigs[_wallet];

        _clearSession(_wallet);

        IWallet(_wallet).setOwner(recoveryOwner);
        _setLock(_wallet, 0, bytes4(0));

        emit RecoveryFinalized(_wallet, recoveryOwner);
    }

    /**
     * @notice Lets the owner cancel an ongoing recovery procedure.
     * Must be confirmed by N guardians, where N = ceil(Nb Guardian at executeRecovery + 1) / 2) - 1.
     * @param _wallet The target wallet.
     */
    function cancelRecovery(address _wallet) external onlySelf() onlyWhenRecovery(_wallet) onlyWhenSecurityEnabled(_wallet) {
        LibSecurityManager.SecurityManagerStorage storage ds = LibSecurityManager.diamondStorage();
        address recoveryOwner = ds.recoveryConfigs[_wallet].recovery;
        delete ds.recoveryConfigs[_wallet];
        _setLock(_wallet, 0, bytes4(0));

        emit RecoveryCanceled(_wallet, recoveryOwner);
    }

    /**
     * @notice Lets the owner transfer the wallet ownership. This is executed immediately.
     * @param _wallet The target wallet.
     * @param _newOwner The address to which ownership should be transferred.
     */
    function transferOwnership(address _wallet, address _newOwner) external onlySelf() onlyWhenUnlocked(_wallet) {
        validateNewOwner(_wallet, _newOwner);
        IWallet(_wallet).setOwner(_newOwner);

        emit OwnershipTransfered(_wallet, _newOwner);
    }

    /**
    * @notice Gets the details of the ongoing recovery procedure if any.
    * @param _wallet The target wallet.
    */
    function getRecovery(address _wallet) external view returns(address _address, uint64 _executeAfter, uint32 _guardianCount) {
        LibSecurityManager.SecurityManagerStorage storage ds = LibSecurityManager.diamondStorage();
        LibSecurityManager.RecoveryConfig storage config = ds.recoveryConfigs[_wallet];
        return (config.recovery, config.executeAfter, config.guardianCount);
    }

    // *************** Lock functions ************************ //

    /**
     * @notice Lets a guardian lock a wallet.
     * @param _wallet The target wallet.
     */
    function lock(address _wallet) external onlyGuardianOrSelf(_wallet) onlyWhenUnlocked(_wallet) onlyWhenSecurityEnabled(_wallet) {
        LibSecurityManager.SecurityManagerStorage storage ds = LibSecurityManager.diamondStorage();
        _setLock(_wallet, block.timestamp + ds.lockPeriod, SecurityManagerFacet.lock.selector);
        emit Locked(_wallet, uint64(block.timestamp + ds.lockPeriod));
    }

    /**
     * @notice Lets a guardian unlock a locked wallet.
     * @param _wallet The target wallet.
     */
    function unlock(address _wallet) external onlyGuardianOrSelf(_wallet) onlyWhenLocked(_wallet) onlyWhenSecurityEnabled(_wallet) {
        require(LibBaseModule._getLock(_wallet).locker == SecurityManagerFacet.lock.selector, "SM: cannot unlock");
        _setLock(_wallet, 0, bytes4(0));
        emit Unlocked(_wallet);
    }

    /**
     * @notice Returns the release time of a wallet lock or 0 if the wallet is unlocked.
     * @param _wallet The target wallet.
     * @return _releaseAfter The epoch time at which the lock will release (in seconds).
     */
    function getLock(address _wallet) external view returns(uint64 _releaseAfter) {
        return _isLocked(_wallet) ? LibBaseModule._getLock(_wallet).release : 0;
    }

    /**
     * @notice Checks if a wallet is locked.
     * @param _wallet The target wallet.
     * @return _isLocked `true` if the wallet is locked otherwise `false`.
     */
    function isLocked(address _wallet) external view returns (bool) {
        return _isLocked(_wallet);
    }

    // *************** Guardian functions ************************ //

    /**
     * @notice Lets the owner add a guardian to its wallet.
     * The first guardian is added immediately. All following additions must be confirmed
     * by calling the confirmGuardianAddition() method.
     * @param _wallet The target wallet.
     * @param _guardian The guardian to add.
     */
    function addGuardian(address _wallet, address _guardian) external onlyWalletOwnerOrSelf(_wallet) onlyWhenUnlocked(_wallet) onlyWhenSecurityEnabled(_wallet) {
        require(!_isOwner(_wallet, _guardian), "SM: guardian cannot be owner");
        require(!isGuardian(_wallet, _guardian), "SM: duplicate guardian");
        // Guardians must either be an EOA or a contract with an owner()
        // method that returns an address with a 25000 gas stipend.
        // Note that this test is not meant to be strict and can be bypassed by custom malicious contracts.
        (bool success,) = _guardian.call{gas: 25000}(abi.encodeWithSignature("owner()"));
        require(success, "SM: must be EOA/Argent wallet");

        if (LibBaseModule._guardianStorage().guardianCount(_wallet) == 0) {
            LibBaseModule._guardianStorage().addGuardian(_wallet, _guardian);
            emit GuardianAdded(_wallet, _guardian);
            return;
        }

        bytes32 id = keccak256(abi.encodePacked(_wallet, _guardian, "addition"));
        LibSecurityManager.SecurityManagerStorage storage ds = LibSecurityManager.diamondStorage();
        LibSecurityManager.GuardianManagerConfig storage config = ds.guardianConfigs[_wallet];
        require(
            config.pending[id] == 0 || block.timestamp > config.pending[id] + ds.securityWindow,
            "SM: duplicate pending addition");
        config.pending[id] = block.timestamp + ds.securityPeriod;
        emit GuardianAdditionRequested(_wallet, _guardian, block.timestamp + ds.securityPeriod);
    }

    /**
     * @notice Confirms the pending addition of a guardian to a wallet.
     * The method must be called during the confirmation window and can be called by anyone to enable orchestration.
     * @param _wallet The target wallet.
     * @param _guardian The guardian.
     */
    function confirmGuardianAddition(address _wallet, address _guardian) external onlyWhenUnlocked(_wallet) onlyWhenSecurityEnabled(_wallet) {
        bytes32 id = keccak256(abi.encodePacked(_wallet, _guardian, "addition"));
        LibSecurityManager.SecurityManagerStorage storage ds = LibSecurityManager.diamondStorage();
        LibSecurityManager.GuardianManagerConfig storage config = ds.guardianConfigs[_wallet];
        require(config.pending[id] > 0, "SM: unknown pending addition");
        require(config.pending[id] < block.timestamp, "SM: pending addition not over");
        require(block.timestamp < config.pending[id] + ds.securityWindow, "SM: pending addition expired");
        LibBaseModule._guardianStorage().addGuardian(_wallet, _guardian);
        emit GuardianAdded(_wallet, _guardian);
        delete config.pending[id];
    }

    /**
     * @notice Lets the owner cancel a pending guardian addition.
     * @param _wallet The target wallet.
     * @param _guardian The guardian.
     */
    function cancelGuardianAddition(address _wallet, address _guardian) external onlyWalletOwnerOrSelf(_wallet) onlyWhenUnlocked(_wallet) onlyWhenSecurityEnabled(_wallet) {
        bytes32 id = keccak256(abi.encodePacked(_wallet, _guardian, "addition"));
        LibSecurityManager.SecurityManagerStorage storage ds = LibSecurityManager.diamondStorage();
        LibSecurityManager.GuardianManagerConfig storage config = ds.guardianConfigs[_wallet];
        require(config.pending[id] > 0, "SM: unknown pending addition");
        delete config.pending[id];
        emit GuardianAdditionCancelled(_wallet, _guardian);
    }

    /**
     * @notice Lets the owner revoke a guardian from its wallet.
     * @dev Revokation must be confirmed by calling the confirmGuardianRevokation() method.
     * @param _wallet The target wallet.
     * @param _guardian The guardian to revoke.
     */
    function revokeGuardian(address _wallet, address _guardian) external onlyWalletOwnerOrSelf(_wallet) onlyWhenSecurityEnabled(_wallet) {
        require(isGuardian(_wallet, _guardian), "SM: must be existing guardian");
        bytes32 id = keccak256(abi.encodePacked(_wallet, _guardian, "revokation"));
        LibSecurityManager.SecurityManagerStorage storage ds = LibSecurityManager.diamondStorage();
        LibSecurityManager.GuardianManagerConfig storage config = ds.guardianConfigs[_wallet];
        require(
            config.pending[id] == 0 || block.timestamp > config.pending[id] + ds.securityWindow,
            "SM: duplicate pending revoke"); // TODO need to allow if confirmation window passed
        config.pending[id] = block.timestamp + ds.securityPeriod;
        emit GuardianRevokationRequested(_wallet, _guardian, block.timestamp + ds.securityPeriod);
    }

    /**
     * @notice Confirms the pending revokation of a guardian to a wallet.
     * The method must be called during the confirmation window and can be called by anyone to enable orchestration.
     * @param _wallet The target wallet.
     * @param _guardian The guardian.
     */
    function confirmGuardianRevokation(address _wallet, address _guardian) external onlyWhenSecurityEnabled(_wallet) {
        bytes32 id = keccak256(abi.encodePacked(_wallet, _guardian, "revokation"));
        LibSecurityManager.SecurityManagerStorage storage ds = LibSecurityManager.diamondStorage();
        LibSecurityManager.GuardianManagerConfig storage config = ds.guardianConfigs[_wallet];
        require(config.pending[id] > 0, "SM: unknown pending revoke");
        require(config.pending[id] < block.timestamp, "SM: pending revoke not over");
        require(block.timestamp < config.pending[id] + ds.securityWindow, "SM: pending revoke expired");
        LibBaseModule._guardianStorage().revokeGuardian(_wallet, _guardian);
        emit GuardianRevoked(_wallet, _guardian);
        delete config.pending[id];
    }

    /**
     * @notice Lets the owner cancel a pending guardian revokation.
     * @param _wallet The target wallet.
     * @param _guardian The guardian.
     */
    function cancelGuardianRevokation(address _wallet, address _guardian) external onlyWalletOwnerOrSelf(_wallet) onlyWhenUnlocked(_wallet) onlyWhenSecurityEnabled(_wallet) {
        bytes32 id = keccak256(abi.encodePacked(_wallet, _guardian, "revokation"));
        LibSecurityManager.SecurityManagerStorage storage ds = LibSecurityManager.diamondStorage();
        LibSecurityManager.GuardianManagerConfig storage config = ds.guardianConfigs[_wallet];
        require(config.pending[id] > 0, "SM: unknown pending revoke");
        delete config.pending[id];
        emit GuardianRevokationCancelled(_wallet, _guardian);
    }

    function enableSecurity(address _wallet) external onlyWalletOwnerOrSelf(_wallet) notWhenSecurityEnabled(_wallet) {
        LibBaseModule._guardianStorage().setSecurityEnabled(_wallet, true);
        emit WalletSecurityEnabled(_wallet);
    }

    function disableSecurity(address _wallet) external onlySelf() onlyWhenUnlocked(_wallet) onlyWhenSecurityEnabled(_wallet) {
        if (LibBaseModule._guardianStorage().guardianCount(_wallet) == 0) {
            LibBaseModule._guardianStorage().setSecurityEnabled(_wallet, false);
            emit WalletSecurityDisabled(_wallet);
            return;
        }
        bytes32 id = keccak256(abi.encodePacked(_wallet, "disableSecurity"));
        LibSecurityManager.SecurityManagerStorage storage ds = LibSecurityManager.diamondStorage();
        LibSecurityManager.GuardianManagerConfig storage config = ds.guardianConfigs[_wallet];
        require(
            config.pending[id] == 0 || block.timestamp > config.pending[id] + ds.securityWindow,
            "SM: duplicate disabling request");
        config.pending[id] = block.timestamp + ds.securityPeriod;
        emit WalletSecurityDisablingRequested(_wallet, block.timestamp + ds.securityPeriod);
    }

    function confirmSecurityDisabling(address _wallet) external onlyWhenUnlocked(_wallet) onlyWhenSecurityEnabled(_wallet) {
        bytes32 id = keccak256(abi.encodePacked(_wallet, "disableSecurity"));
        LibSecurityManager.SecurityManagerStorage storage ds = LibSecurityManager.diamondStorage();
        LibSecurityManager.GuardianManagerConfig storage config = ds.guardianConfigs[_wallet];
        require(config.pending[id] > 0, "SM: unknown disabling request");
        require(config.pending[id] < block.timestamp, "SM: pending not over");
        require(block.timestamp < config.pending[id] + ds.securityWindow, "SM: pending expired");
        LibBaseModule._guardianStorage().setSecurityEnabled(_wallet, false);
        emit WalletSecurityDisabled(_wallet);
        delete config.pending[id];
    }

    function cancelSecurityDisabling(address _wallet) external onlyWalletOwnerOrSelf(_wallet) onlyWhenSecurityEnabled(_wallet) {
        bytes32 id = keccak256(abi.encodePacked(_wallet, "disableSecurity"));
        LibSecurityManager.SecurityManagerStorage storage ds = LibSecurityManager.diamondStorage();
        LibSecurityManager.GuardianManagerConfig storage config = ds.guardianConfigs[_wallet];
        require(config.pending[id] > 0, "SM: unknown disabling request");
        delete config.pending[id];
        emit WalletSecurityDisablingCancelled(_wallet);
    }


    /**
     * @notice Checks if an address is a guardian for a wallet.
     * @param _wallet The target wallet.
     * @param _guardian The address to check.
     * @return _isGuardian `true` if the address is a guardian for the wallet otherwise `false`.
     */
    function isGuardian(address _wallet, address _guardian) public view returns (bool _isGuardian) {
        return LibBaseModule._guardianStorage().isGuardian(_wallet, _guardian);
    }

    /**
    * @notice Checks if an address is a guardian or an account authorised to sign on behalf of a smart-contract guardian.
    * @param _wallet The target wallet.
    * @param _guardian the address to test
    * @return _isGuardian `true` if the address is a guardian for the wallet otherwise `false`.
    */
    function isGuardianOrGuardianSigner(address _wallet, address _guardian) external view returns (bool _isGuardian) {
        (_isGuardian, ) = Utils.isGuardianOrGuardianSigner(LibBaseModule._guardianStorage().getGuardians(_wallet), _guardian);
    }

    /**
     * @notice Counts the number of active guardians for a wallet.
     * @param _wallet The target wallet.
     * @return _count The number of active guardians for a wallet.
     */
    function guardianCount(address _wallet) external view returns (uint256 _count) {
        return LibBaseModule._guardianStorage().guardianCount(_wallet);
    }

    /**
     * @notice Get the active guardians for a wallet.
     * @param _wallet The target wallet.
     * @return _guardians the active guardians for a wallet.
     */
    function getGuardians(address _wallet) external view returns (address[] memory _guardians) {
        return LibBaseModule._guardianStorage().getGuardians(_wallet);
    }

    // *************** Internal Functions ********************* //

    function validateNewOwner(address _wallet, address _newOwner) internal view {
        require(_newOwner != address(0), "SM: new owner cannot be null");
        require(!isGuardian(_wallet, _newOwner), "SM: new owner cannot be guardian");
    }

    function _setLock(address _wallet, uint256 _releaseAfter, bytes4 _locker) internal {
        // locks[_wallet] = Lock(SafeCast.toUint64(_releaseAfter), _locker);
        LibBaseModule._setLock(_wallet, SafeCast.toUint64(_releaseAfter), _locker);
    }
}
