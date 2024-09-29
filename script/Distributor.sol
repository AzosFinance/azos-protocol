pragma solidity ^0.8.20;

contract Distributor {
  function distribute(address[] memory _recipients)
    public
    payable
    returns (uint256 _amount, address[] memory _returnedRecipients)
  {
    _amount = msg.value / _recipients.length;
    for (uint256 _i = 0; _i < _recipients.length; _i++) {
      (bool _success,) = payable(_recipients[_i]).call{value: _amount}('');
      require(_success, 'Transfer failed');
    }
    return (_amount, _recipients);
  }
}
