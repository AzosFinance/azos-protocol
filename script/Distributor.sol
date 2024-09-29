pragma solidity ^0.8.19;

contract Distributor {
  function distribute(address[] memory recipients) public payable returns (uint256, address[] memory) {
    uint256 amount = msg.value / recipients.length;
    for (uint256 i = 0; i < recipients.length; i++) {
      (bool success,) = payable(recipients[i]).call{value: amount}('');
      require(success, 'Transfer failed');
    }
    return (amount, recipients);
  }
}