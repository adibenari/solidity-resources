contract DougEnabled {
    address DOUG;

    function setDougAddress(address dougAddr) returns (bool result){
        // Once the doug address is set, don't allow it to be set again, except by the
        // doug contract itself.
        if(DOUG != 0x0 && dougAddr != DOUG){
            return false;
        }
        DOUG = dougAddr;
        return true;    
    }

    // Makes it so that Doug is the only contract that may kill it.
    function remove(){
        if(msg.sender == DOUG){
            suicide(DOUG);
        }
    }

}

contract ContractProvider {
    function contracts(string32 name) returns (address addr) {} 
}

contract FundManagerEnabled is DougEnabled {

    // Makes it easier to check that fundmanager is the caller.
    function isFundManager() constant returns (bool) {
        if(DOUG != 0x0){
            address fm = ContractProvider(DOUG).contracts("fundmanager");
            return msg.sender == fm;
        }
        return false;
    }
}

// The bank database
contract BankDb is DougEnabled {

    function deposit(address addr) constant returns (bool res) {
    }

    function withdraw(address addr, uint amount) constant returns (bool res) {
    }

}

// The bank
contract Bank is FundManagerEnabled {

    // Attempt to withdraw the given 'amount' of Ether from the account.
    function deposit(address userAddr) constant returns (bool res) {
        if (!isFundManager()){
            return false;
        }
        address bankdb = ContractProvider(DOUG).contracts("bankdb");
        if ( bankdb == 0x0 ) {
            // If the user sent money, we should return it if we can't deposit.
            msg.sender.send(msg.value);
            return false;
        }

        // Use the interface to call on the bank contract. We pass msg.value along as well.
        bool success = BankDb(bankdb).deposit.value(msg.value)(userAddr);

        // If the transaction failed, return the Ether to the caller.
        if (!success) {
            msg.sender.send(msg.value);
        }
        return success;
    }

    // Attempt to withdraw the given 'amount' of Ether from the account.
    function withdraw(address userAddr, uint amount) constant returns (bool res) {
        if (!isFundManager()){
            return false;
        }
        address bankdb = ContractProvider(DOUG).contracts("bankdb");
        if ( bankdb == 0x0 ) {
            return false;
        }

        // Use the interface to call on the bank contract.
        bool success = BankDb(bankdb).withdraw(userAddr, amount);

        // If the transaction succeeded, pass the Ether on to the caller.
        if (success) {
            userAddr.send(amount);
        }
        return success;
    }

}