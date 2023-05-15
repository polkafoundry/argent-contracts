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

import "../../common/IModule.sol";
import "./BaseFacet.sol";
import "../libraries/LibBaseModule.sol";
import "../../common/Utils.sol";
import "../../../../lib_0.5/other/ERC20.sol";

contract ArgentModuleFacet is BaseFacet, IModule {
    bytes32 constant public NAME = "ArgentModule";
    bytes4 private constant ERC1271_IS_VALID_SIGNATURE = bytes4(keccak256("isValidSignature(bytes32,bytes)"));
    bytes4 private constant ERC721_RECEIVED = bytes4(keccak256("onERC721Received(address,address,uint256,bytes)"));
    bytes4 private constant ERC1155_RECEIVED = bytes4(keccak256("onERC1155Received(address,address,uint256,uint256,bytes)"));
    bytes4 private constant ERC1155_BATCH_RECEIVED = bytes4(keccak256("onERC1155BatchReceived(address,address,uint256[],uint256[],bytes)"));
    bytes4 private constant ERC165_INTERFACE = bytes4(keccak256("supportsInterface(bytes4)"));

    /**
     * @inheritdoc IModule
     */
    function init(address _wallet) external override onlyWallet(_wallet) {
        enableDefaultStaticCalls(_wallet);
    }

    /**
    * @inheritdoc IModule
    */
    function addModule(address _wallet, address _module) external override onlyWalletOwnerOrSelf(_wallet) onlyWhenUnlocked(_wallet) {
        require(LibBaseModule._registry().isRegisteredModule(_module), "AM: module is not registered");
        IWallet(_wallet).authoriseModule(_module, true);
    }

    function supportsStaticCall(bytes4 _methodId) external pure override returns (bool _isSupported) {
        return _methodId == ERC1271_IS_VALID_SIGNATURE ||
               _methodId == ERC721_RECEIVED ||
               _methodId == ERC165_INTERFACE ||
               _methodId == ERC1155_RECEIVED ||
               _methodId == ERC1155_BATCH_RECEIVED;
    }

    function enableDefaultStaticCalls(address _wallet) internal {
        // setup the static calls that are available for free for all wallets
        IWallet(_wallet).enableStaticCall(address(this), ERC1271_IS_VALID_SIGNATURE);
        IWallet(_wallet).enableStaticCall(address(this), ERC721_RECEIVED);
    }

    /**
     * @notice Moves tokens that have been sent to the module by mistake.
     * @param _token The target token.
     */
    function recoverToken(address _token) external {
        uint total = ERC20(_token).balanceOf(address(this));
        ERC20(_token).transfer(address(LibBaseModule._registry()), total);
    }
}