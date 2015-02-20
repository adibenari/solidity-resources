contract DougEnabled {
    address DOUG;

    function setDougAddress(address dougAddr) returns (bool result){
    }

    // Makes it so that Doug is the only contract that may kill it.
    function remove(){
    }

}

// The Doug contract.
contract Doug {

    address owner;

    // This is where we keep all the contracts.
    mapping (string32 => address) public contracts;

    // Constructor
    function Doug(){
        owner = msg.sender;
    }

    // Add a new contract to Doug. This will overwrite an existing contract.
    function addContract(string32 name, address addr) constant returns (bool result) {
        if(msg.sender != owner){
            return false;
        }
        DougEnabled de = DougEnabled(addr);
        // Don't add the contract if this does not work.
        if(!de.setDougAddress(address(this))) {
            return false;
        }
        contracts[name] = addr;
        return true;
    }

    // Remove a contract from Doug. We could also suicide if we want to.
    function removeContract(string32 name) constant returns (bool result) {
        if (contracts[name] == 0x0){
            return false;
        }
        if(msg.sender != owner){
            return false;
        }
        contracts[name] = 0x0;
        return true;
    }

    function remove(){

        if(msg.sender == owner){

            address fm = contracts["fundmanager"];
            address perms = contracts["perms"];
            address permsdb = contracts["permsdb"];
            address bank = contracts["bank"];
            address bankdb = contracts["bankdb"];

            // Remove everything.
            if(fm != 0x0){ DougEnabled(fm).remove(); }
            if(perms != 0x0){ DougEnabled(perms).remove(); }
            if(permsdb != 0x0){ DougEnabled(permsdb).remove(); }
            if(bank != 0x0){ DougEnabled(bank).remove(); }
            if(bankdb != 0x0){ DougEnabled(bankdb).remove(); }

            // Finally, remove doug. Doug will now have all the funds of the other contracts, 
            // and when suiciding it will all go to the owner.
            suicide(owner);
        }
    }

}