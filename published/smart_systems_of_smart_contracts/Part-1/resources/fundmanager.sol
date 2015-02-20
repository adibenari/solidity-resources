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

// Permissions database
contract PermissionsDb is DougEnabled {

	mapping (address => uint8) public perms;

    // Set the permissions of an account.
    function setPermission(address addr, uint8 perm) constant returns (bool res) {
    }

}

// Permissions
contract Permissions is FundManagerEnabled {

    // Set the permissions of an account.
    function setPermission(address addr, uint8 perm) constant returns (bool res) {
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
    }

    // Attempt to withdraw the given 'amount' of Ether from the account.
    function withdraw(address userAddr, uint amount) constant returns (bool res) {
    }

}

// The fund manager
contract FundManager is DougEnabled {

    // We still want an owner.
    address owner;

    // Constructor
    function FundManager(){
        owner = msg.sender;
    }

    // Attempt to withdraw the given 'amount' of Ether from the account.
    function deposit() constant returns (bool res) {
        if (msg.value == 0){
            return false;
        }
        address bank = ContractProvider(DOUG).contracts("bank");
        address permsdb = ContractProvider(DOUG).contracts("permsdb");
        if ( bank == 0x0 || permsdb == 0x0 || PermissionsDb(permsdb).perms(msg.sender) < 1) {
            // If the user sent money, we should return it if we can't deposit.
            msg.sender.send(msg.value);
            return false;
        }

        // Use the interface to call on the bank contract. We pass msg.value along as well.
        bool success = Bank(bank).deposit.value(msg.value)(msg.sender);

        // If the transaction failed, return the Ether to the caller.
        if (!success) {
            msg.sender.send(msg.value);
        }
        return success;
    }

    // Attempt to withdraw the given 'amount' of Ether from the account.
    function withdraw(uint amount) constant returns (bool res) {
        if (amount == 0){
            return false;
        }

        address bank = ContractProvider(DOUG).contracts("bank");
        address permsdb = ContractProvider(DOUG).contracts("permsdb");
        if ( bank == 0x0 || permsdb == 0x0 || PermissionsDb(permsdb).perms(msg.sender) < 1) {
            // If the user sent money, we should return it if we can't deposit.
            msg.sender.send(msg.value);
            return false;
        }

        // Use the interface to call on the bank contract.
        bool success = Bank(bank).withdraw(msg.sender, amount);

        // If the transaction succeeded, pass the Ether on to the caller.
        if (success) {
            msg.sender.send(amount);
        }
        return success;
    }

    // Set the permissions for a given address.
    function setPermission(address addr, uint8 permLvl) constant returns (bool res) {
        if (msg.sender != owner){
            return false;
        }
        address perms = ContractProvider(DOUG).contracts("perms");
        if ( perms == 0x0 ) {
            return false;
        }
        return Permissions(perms).setPermission(addr,permLvl);
    }

}