// SPDX-License-Identifier: MIT
pragma solidity 0.8.4;

import "@openzeppelin/contracts/access/Ownable.sol";
import "hardhat/console.sol";

contract Streamer is Ownable {
    event Opened(address, uint256);
    event Challenged(address);
    event Withdrawn(address, uint256);
    event Closed(address);

    mapping(address => uint256) balances;
    mapping(address => uint256) canCloseAt;

    function fundChannel() public payable {
        if (balances[msg.sender] != 0) {
            revert();
        } else {
            balances[msg.sender] = msg.value;
            emit Opened(msg.sender, msg.value);
        }
    }

    function timeLeft(address channel) public view returns (uint256) {
        require(canCloseAt[channel] != 0, "channel is not closing");
        return canCloseAt[channel] - block.timestamp;
    }

    function withdrawEarnings(Voucher calldata voucher) public onlyOwner() {
        // like the off-chain code, signatures are applied to the hash of the data
        // instead of the raw data itself
        bytes32 hashed = keccak256(abi.encode(voucher.updatedBalance));

        // The prefix string here is part of a convention used in ethereum for signing
        // and verification of off-chain messages. The trailing 32 refers to the 32 byte
        // length of the attached hash message.
        //
        // There are seemingly extra steps here compared to what was done in the off-chain
        // `reimburseService` and `processVoucher`. Note that those ethers signing and verification
        // functions do the same under the hood.
        //
        // see https://blog.ricmoo.com/verifying-messages-in-solidity-50a94f82b2ca
        bytes memory prefixed = abi.encodePacked(
            "\x19Ethereum Signed Message:\n32",
            hashed
        );
        bytes32 prefixedHashed = keccak256(prefixed);

        address recoveredSigner = ecrecover(
            prefixedHashed,
            voucher.sig.v,
            voucher.sig.r,
            voucher.sig.s
        );

        require(balances[recoveredSigner] > voucher.updatedBalance, "Balance signer not enough for updatedBalance");
        uint256 payoutAmount = balances[recoveredSigner] - voucher.updatedBalance;

        balances[recoveredSigner] = voucher.updatedBalance;
        address ownerAddress = owner();

        (bool success, ) = payable(ownerAddress).call{value: payoutAmount}("");
        require(success, "Withdrawal failure");

        emit Withdrawn(ownerAddress, payoutAmount);
    }

    function challengeChannel() public {
        require(balances[msg.sender] != 0, "Sender does not have open channel");
        canCloseAt[msg.sender] = block.timestamp + 60 seconds;

        emit Challenged(msg.sender);
    }

    function defundChannel() public {
        require(canCloseAt[msg.sender] != 0, "Channel has not been challenged.");
        require(block.timestamp > canCloseAt[msg.sender], "Channel is still in challenge period.");

        uint256 remainingBalance = balances[msg.sender];
        balances[msg.sender] = 0;

        (bool success, ) = payable(msg.sender).call{value: remainingBalance}("");
        require(success, "Withdrawal failure");

        emit Closed(msg.sender);
    }

    struct Voucher {
        uint256 updatedBalance;
        Signature sig;
    }
    struct Signature {
        bytes32 r;
        bytes32 s;
        uint8 v;
    }
}
