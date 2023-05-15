// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

/******************************************************************************\
* Author: Nick Mudge <nick@perfectabstractions.com> (https://twitter.com/mudgen)
* EIP-2535 Diamonds: https://eips.ethereum.org/EIPS/eip-2535
*
* Implementation of a diamond.
/******************************************************************************/

import { LibDiamond } from "../libraries/LibDiamond.sol";
import { IDiamondLoupe } from "../interfaces/IDiamondLoupe.sol";
import { IDiamondCut } from "../interfaces/IDiamondCut.sol";
// import { IERC173 } from "../interfaces/IERC173.sol";
import { IERC165 } from "../interfaces/IERC165.sol";

import "../libraries/LibBaseModule.sol";
import "../libraries/LibRelayerManager.sol";
import "../libraries/LibSecurityManager.sol";
import "../libraries/LibTransactionManager.sol";

import "argent-trustlists/contracts/interfaces/IAuthoriser.sol";
import "../../../infrastructure/IModuleRegistry.sol";
import "../../../infrastructure/storage/IGuardianStorage.sol";
import "../../../infrastructure/storage/ITransferStorage.sol";

// It is expected that this contract is customized if you want to deploy your diamond
// with data from a deployment script. Use the init function to initialize state variables
// of your diamond. Add parameters to the init funciton if you need to.

// Adding parameters to the `init` or other functions you add here can make a single deployed
// DiamondInit contract reusable accross upgrades, and can be used for multiple diamonds.

contract DiamondInit {
    bytes4 private constant ERC1155_RECEIVED = bytes4(keccak256("onERC1155Received(address,address,uint256,uint256,bytes)"));
    bytes4 private constant ERC1155_BATCH_RECEIVED = bytes4(keccak256("onERC1155BatchReceived(address,address,uint256[],uint256[],bytes)"));

    // You can add parameters to this function in order to pass in 
    // data to set your own state variables
    function init(
        IModuleRegistry _registry,
        IGuardianStorage _guardianStorage,
        ITransferStorage _userWhitelist,
        IAuthoriser _authoriser,
        address _uniswapRouter,
        uint256 _securityPeriod,
        uint256 _securityWindow,
        uint256 _recoveryPeriod,
        uint256 _lockPeriod
    ) external {
        // adding ERC165 data
        LibDiamond.DiamondStorage storage ds = LibDiamond.diamondStorage();
        ds.supportedInterfaces[type(IERC165).interfaceId] = true;
        ds.supportedInterfaces[type(IDiamondCut).interfaceId] = true;
        ds.supportedInterfaces[type(IDiamondLoupe).interfaceId] = true;
        // ds.supportedInterfaces[type(IERC173).interfaceId] = true;
        ds.supportedInterfaces[ERC1155_RECEIVED ^ ERC1155_BATCH_RECEIVED] = true; // ERC1155

        // add your own state variables 
        // EIP-2535 specifies that the `diamondCut` function takes two optional 
        // arguments: address _init and bytes calldata _calldata
        // These arguments are used to execute an arbitrary function using delegatecall
        // in order to set state variables in the diamond during deployment or an upgrade
        // More info here: https://eips.ethereum.org/EIPS/eip-2535#diamond-interface

        LibBaseModule.BaseModuleStorage storage bs = LibBaseModule.diamondStorage();
        bs.registry = _registry;
        bs.guardianStorage = _guardianStorage;
        bs.userWhitelist = _userWhitelist;
        bs.authoriser = _authoriser;

        LibSecurityManager.SecurityManagerStorage storage ss = LibSecurityManager.diamondStorage();
        require(_lockPeriod >= _recoveryPeriod, "SM: insecure lock period");
        require(_recoveryPeriod >= _securityPeriod + _securityWindow, "SM: insecure security periods");
        ss.recoveryPeriod = _recoveryPeriod;
        ss.lockPeriod = _lockPeriod;
        ss.securityWindow = _securityWindow;
        ss.securityPeriod = _securityPeriod;

        LibTransactionManager.TransactionManagerStorage storage ts = LibTransactionManager.diamondStorage();
        ts.whitelistPeriod = _securityPeriod;

        LibRelayerManager.init(_uniswapRouter);
    }
}
