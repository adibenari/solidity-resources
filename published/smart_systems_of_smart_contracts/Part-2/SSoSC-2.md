##Smart systems of smart contracts 
**Part 2: An action driven architecture**

*By: Andreas Olofsson (andreas@erisindustries.com)*

Here I'm going to propose an architecture that can be used for medium-sized and even large systems. It is scalable, secure, and it also has a massive proof-of-concept system behind it. This system is called The People's republic of Doug, and works somewhat like a government (https://github.com/androlo/EthereumContracts). It has banking, citizenship/titles, voting, a forum, and other things. All in all it has about 70 unique contracts that are made up of about 20k lines of LLL contract code, and it ran on the early Ethereum test-chains.

###Actions

PRODOUG was made secure by encapsulating all the code that users could run in something called actions. All incoming transactions had to be on a specific format, and had to be send to the 'action manager' contract (except certain "light" transactions made to external services). Here's an example of how a super simple action interface could look in Solidity:

``` javascript
contract SomeAction {
	function execute(type1 par1, type2 par2, ....) constant return (bool result) {}
}
```

The way you manage and call action contract is by keeping references to them in a manager contract:

``` javascript
// Keep the interface here.
contract SomeAction {
	// This is used to carry out the action.
	function execute(type1 par1, type2 par2, ....) constant returns (bool ) {}
}

// The action manager
contract ActionManager {
	
	// This is where we keep all the actions.
	mapping (string32 => address) actions;
        
	// Note: arrays cannot be function parameters yet.
	function execute(string32 actionName, bytes data) constant returns (bool) {
		address actn = actions[actionName];
		// If no action with the given name exists - cancel.
		if (actn == 0x0){
			return false;
		}
		return Action(actn).call(data);
	}

	// Add a new action.
	function addAction(string32 name, address addr) {
		actions[name] = addr;
	}

	// Remove an action.
	function removeAction(string32 name) constant returns (bool) {
		if (actions[name] == 0x0){
			return false;
		}
		actions[name] = 0x0;
		return true;
	}

}
```

If you have read part 1, you'll notice notice that we're cheating here by adding the actions map to the action manager itself, which is wrong (and not how it's done in PRODOUG). The final contract version will delegate to a database contract. Also there's no real security yet, but at least we have a simple action system to start with. People can add actions to it, remove them, and execute them, but before we can add any actions to it we have to add another component - the top level CMC (contract managing contract, see part 1), or "DOUG". Doug is the contract that keeps track of all other contracts in the system. We'll start with a namereg type contract similar to the one in part 1.

``` javascript
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
    	 address cName = contracts[name];
        if (cName == 0x0){
            return false;
        }
        if(msg.sender != owner){
            return false;
        }
        // Kill any contracts we remove, for now.
        DougEnabled(cName).remove();
        contracts[name] = 0x0;
        return true;
    }

    function remove(){
        if(msg.sender == owner){
            suicide(owner);
        }
    }

}

```

We will also add a super simple bank contract.

``` javascript
// The Bank contract
contract Bank {
	
	// This is where we keep all the permissions.
	mapping (address => uint) public balances;

	// Endow an address with coins.
	function endow(address addr, uint amount) {
		balances[addr] += amount;
	}

	// Charge an account 'amount' number of coins.
	function charge(address addr, uint amount) constant returns (bool){
		if (balances[addr] < amount){
			// Bounces if balance is lower then the amount charged.
			return false;
		}
		balances[addr] -= amount;
		return true;
	}

}
```

What we would do in order to run a system like this is to deploy as such:

1) Deploy the DOUG contract.
2) Deploy the action manager contract and register it with the DOUG contract under the name "actions".
3) Deploy the bank contract and register it with the DOUG contract under the name "bank".

What we need do next is to add an action for endowing an address with coins, and one for charging it. We need to add one more function to the actions interface though - the setDougAddress function. This function is what will give actions (indirect) access to all the contracts in the system so they can carry out their work. It is also an important security measure. We will use the DougEnabled contract from part 1.

``` javascript
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
```

The basic action template starts like this:

``` javascript
contract Action is DougEnabled {}
```

Note that we don't include an 'execute' signature, as it is too generic and Solidity does not support generic signatures. We will add the execute function on a per-action basis for now. 

To lock these contracts down even more, we only allow the contract currently registered as `actions` to call the functions. Much like the `FundManagerEnabled` contract in part 1.

``` javascript
contract ContractProvider {
	function contracts(string32 name) returns (address){}
}

contract ActionManagerEnabled is DougEnabled {
	// Makes it easier to check that action manager is the caller.
	function isActionManager() inheritable constant returns (bool) {
		if(DOUG != 0x0){
			address am = ContractProvider(DOUG).contracts("actions");
			if (msg.sender == am){
		        return true;		
			}
		}
		return false;
	}
}
```

This means the new action base class is this:


``` javascript
contract Action is ActionManagerEnabled {}
```

Here's the endow action contract.

``` javascript
// The Bank contract (the "sub interface" we need).
contract Endower {
	function endow(address addr, uint amount) {}
}

// The endow action.
contract ActionEndow is Action {

	function execute(address addr, uint amount) constant returns (bool) {
		if(!isActionManager()){
			return false;
		}
		ContractProvider dg = ContractProvider(DOUG);
		address endower = dg.getContract("bank");
		if(endower == 0x0){
			return false;
		}
		Endower(endower).endow(addr, amount);
		return true;
	}
}
```

This is the action for charging.

``` javascript

// The Bank contract (or the "sub interface" we need).
contract Charger {
	function charge(address addr, uint amount) constant returns (bool) {}
}

// The charge action.
contract ActionCharge {
	
	function execute(address addr, uint amount) constant returns (bool) {
		if(!isActionManager()){
			return false;
		}
		ContractProvider dg = ContractProvider(DOUG);
		address charger = dg.getContract("bank");
		if(charger == 0x0){
			return false;
		}
		Charger(charger).charge(addr,amount);
		return true;
	}
	
}
```

When we add these actions to the action manager it will be possible for users to execute them and work with the bank contract that way, but it is still possible to interact the bank contract directly so the actions are not really useful. That's what we're going to change that next.

###Permissions

Step 2 is to control which of the contracts in the doug cluster that can be accessed from the outside. It should only be possible to interact with the contracts through actions, and it should only be possible to run actions through the actions manager. The first thing we need to do is make sure the action manager  calls the 'setDougAddress' function that we added to the actions. It should call it and pass the DOUG address to the action as soon as it's registered. If the function returns false, that means it already has a doug address set, which in turn means the actions should not be registered with the action manager at all.

We also need to add the DOUG address to the action manager. In fact, the bank and all other contracts like it should have a function that allows the DOUG value to be set so we'll just doug-enable all of them.

The action manager will also get a 'validate' function that can be called by other contracts to ensure that only actions can call them, and finally we will also break out the actions list into a separate database contract.

Finally, we will separate the actions database from the action manager as per the recommendations in part 1.

**The updated contracts**

This is the new action manager. We're adding the setDougAddress functionality when adding actions and also an 'active contract' field that will be used for validation. We will make `ActionDb`callable only from the action manager now, but there will be an even better system later.

``` javascript
contract ActionDb is ActionManagerEnabled {
	
	// This is where we keep all the actions.
	mapping (string32 => address) public actions;
   
	function addAction(string32 name, address addr) constant returns (bool) {
		if(!isActionManager()){
			return false;
		}
		actions[name] = addr;
		return true;
	}

	function removeAction(string32 name) constant returns (bool) {
		if(!isActionManager()){
			return false;
		}
		if (actions[name] == 0x0){
			return false;
		}
		actions[name] = 0x0;
		return true;
	}

}
```

``` javascript
// The new action manager.
contract ActionManager is DougEnabled {

	// This is where we keep the "active action".
	address activeAction;
	
	function ActionManager(){
	}
        
	function execute(string32 actionName, bytes data) constant returns (bool) {
		address actionDb = ContractProvider(DOUG).contracts("actiondb");
		if (actionDb == 0x0){
			return false;
		}
		address actn = ActionDb(actionDb).actions(actionName);
		// If no action with the given name exists - cancel.
		if (actn == 0x0){
			return false;
		}
		// Set this as the currently active action.
		activeAction = actn;
		// Run the action. Any contract that calls 'validate' now will only get 'true' if the 
		// calling contract is 'actn'.
		bool b = actn.call(data);
		// Now clear it.
		activeAction = 0x0;
		return b;
	}

	function addAction(string32 name, address addr) constant returns (bool) {
		address actionDb = ContractProvider(DOUG).contracts("actiondb");
		if (actionDb == 0x0){
			return false;
		}
		bool res = ActionDb(actionDb).addAction(name,addr);
		return res;
	}

	function removeAction(string32 name) constant returns (bool) {
		address actionDb = ContractProvider(DOUG).contracts("actiondb");
		if (actionDb == 0x0){
			return false;
		}
		bool res = ActionDb(actionDb).removeAction(name);
		return res;
	}

	// Validate can be called by a contract like the bank to check if the
	// contract calling it has permissions to do so.
	function validate(address addr) constant returns (bool) {
		return addr == activeAction;
	}	

}
```

Here is the new bank:

``` javascript

// Interaction with the action manager.
contract Validator {
	function validate(address addr) constant returns (bool) {}
}

// The Bank contract - now inherits DougEnabled
contract Bank is DougEnabled {

	// Endow an address with coins.        
	function endow(address addr, uint amount) constant returns (bool) {
		address actns = ContractProvider(DOUG).getContract("actions");
		if (actns == 0x0){
			return false;
		}
		
		Validator v = Validator(actns);
		// If the sender is not validated successfully, break.
		if (!v.validate(msg.sender)){
			return false;
		}
		balance[addr] += amount;
		return true;
	}

	// Charge an account 'amount' number of coins.
	function charge(address addr, uint amount) constant returns (bool){
		address actns = ContractProvider(DOUG).getContract("actions");
		if (actns == 0x0){
			return;
		}
		
		Validator v = Validator(actns);
		// If the sender is not validated successfully, break.
		if (!v.validate(msg.sender)){
			return false;
		}
		
		if (balance[addr] < amount){
			return false;
		}

		balance[addr] -= amount;
		return true;
	}

}
```


What we have now is a system that allows us to add contracts (any contracts) to DOUG, and actions. The contracts can not be called except through actions, which means that we can control who gets to call the contracts by controlling who gets to execute actions, and since the actions are all handled in a similar way it will be easy to do that. 

There is other benefits to a system like this as well, for example PRODOUG used the fact that all transactions went through the action manager to log them. The log included data such as the caller address, which action was called, the number of the block in which the tx was added, etc. This is a useful thing to do if you want to keep track of what's going on.

###Locking things down

The last thing we have to fix is access to DOUG and the action manager. It is true that the bank and other contracts must be called via actions, but anyone is allowed to add and remove actions, and also to add and remove contracts from DOUG. We're going to start by adding a simple permissions contract that we can use to set permissions for accounts. It'll be registered with DOUG under the name "perms". We're then going to add functions to actions where permissions can be gotten and set. Finally we will complement the system with the following basic actions:

- add action
- remove action
- add contract
- remove contract
- set account permissions
- modify action permissions

Note that there will be an add action action. This will actually be hard coded into the action database upon creation, but can be replaced later (through the add action action itself). 

*Pro tip: Don't remove the add action action.*

``` javascript

// The Permissions contract
contract Permissions is DougEnabled {
	
	// This is where we keep all the permissions.
	mapping (address => uint8) public perms;
        
	function setPermission(address addr, uint8 perm) constant returns (bool) {
		address actns = ContractProvider(DOUG).getContract("actions");
		if (actns == 0x0){
			return false;
		}
		Validator v = Validator(actns);
		// If the sender is not validated successfully, break.
		if (!v.validate(msg.sender)) {
			return false;
		}
		
		perms[addr] = addr;
	}
	
}
```

Next we will modify the actions template so that it is possible to get and set the permissions required to execute them. We will add the following functions to the interface:

``` javascript
function getPremission() constant returns (uint) {}
function setPermission(uint8 permVal) constant returns (bool) {}
```

This is how we'd update the action managers execute function.

``` javascript

// For getting permissions.
contract Permissioner {
	function perms(address addr) constant returns (uint8) { }
}

// This is how the new execute function would look in the ActionManager contract.

function execute(string32 actionName, bytes data) constant returns (bool) {
	
	...

	// Permissions stuff
	address pAddr = ContractProvider(DOUG).getContract("perms");
	if(pAddr == 0x0){
		return false;
	}
	Permissioner p = Permissioner(pAddr);
	
	// First we check the permissions of the account that's trying to execute the action.
	uint8 perm = p.getPermission(msg.sender);
	// Now we check the permission that is required to execute the action.
	uint8 permReq = Action(actn).getPermission();
	// Very simple system.
	if (perm < permReq){
		return false;
	}

	// Proceed to execute the action.

	...
	
}
```

Before assembling a list of the final contracts, we need to do some final modifications. For example, when adding and removing actions to the action manager it will basically have to validate against itself. It can just check its `activeAction` field directly instead of calling `validate`.

Doug will also have to be modified. We need it to validate the account when someone is trying to add a contract. This is a bit weird, because how then would you go about adding the action manager contract? The way it worked in PRODOUG was to check if the action manager is there. If there is no action manager then just allow anything. Adding the action manager is what you'd use to lock the system down.

Also, what about removing? How do we remove Doug? Whoever is allowed to do that can kill the entire system with one press of a button, so this would often have to be regulated somehow, but if it's a normal dapp that has an owner it could be as easy as giving the owner the exclusive right to kill the DOUG contract. It does not have to be the same in every system.

Finally, this is just a basic action driven architecture. You'd normally extend it. PRODOUG for example had voting. This ment actions sometimes could not be carried out directly, instead the action would spawn a copy of itself, and be kept in a temporary list until the vote had been carried out. Those types of actions had an init function where all the parameters was set, and then an execute function that was carrried out when a vote was concluded. The way it worked with permissions was that actions did not return a number when asked for the required permission but a name of a poll type. These poll types was kept in a list in a different manager that handled polls. Sometimes the polls were automatic (based on some user property) and sometimes there was a full-on vote with time limits, a quorums and other things.


###The finished contracts


Pure interfaces:

``` javascript

// Implemented by the action manager.
contract Validator {
	function validate(address addr) constant returns (bool) {}
}

// Implemented by the action manager.
contract ActionManager {
	function addAction(string32 name, address addr) constant returns (bool) {}
	function removeAction(string32 name) constant returns (bool) {}
	function getAction(string32 name) returns (address addr) {}
}

// Implemented by Doug.
contract ContractProvider {
	function contracts(string32 name) returns (address) {}
}

// Implemented by Doug.
contract ContractRegistry {
	function addContract(string32 name) returns (address addr) {}
	function removeContract(string32 name) constant returns (bool result) {}
}

// Implemented by the bank contract.
contract Endower {
	function endow(address addr, uint amount) constant returns (bool){}
}

// Implemented by the bank contract.
contract Charger {
	function charge(address addr, uint amount) constant returns (bool) {}
}

// Implemented by the permissions contract.
contract Permissioner {
	function perms(address addr) constant returns (uint8) {}
}

// Implemented by the permissions contract.
contract PermissionSetter {
	function setPermission(address addr, uint8 perm) constant returns (bool) {}
}

```

Basic contracts:

``` javascript
// Base class for contracts that are used in a doug system.
ccontract DougEnabled {
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

// Base class for contracts that are doing validation against an action manager.
contract Validating is DougEnabled {
    address DOUG;

    function isValid() constant returns (bool){
        if(DOUG == 0x0){
            return false;
        }
        address amAddr = ContractProvider(DOUG).contracts("actions");
        if(actions == 0x0){
            return false;
        }
        return Validator(amAddr).validate(msg.sender);
    }

}

contract ActionManagerEnabled is DougEnabled {
    // Makes it easier to check that action manager is the caller.
    function isActionManager() inheritable constant returns (bool) {
        if(DOUG != 0x0){
            address am = ContractProvider(DOUG).contracts("actions");
            if (msg.sender == am){
                return true;        
            }
        }
        return false;
    }
}
```

Contracts:


``` javascript

contract ActionDb is ActionManagerEnabled {

    // This is where we keep all the actions.
    mapping (string32 => address) public actions;

    function addAction(string32 name, address addr) constant returns (bool) {
        if(!isActionManager()){
            return false;
        }
        actions[name] = addr;
        return true;
    }

    function removeAction(string32 name) constant returns (bool) {
        if(!isActionManager()){
            return false;
        }
        if (actions[name] == 0x0){
            return false;
        }
        actions[name] = 0x0;
        return true;
    }

}

// The new action manager.
contract ActionManager is DougEnabled {

    // This is where we keep the "active action".
    address activeAction;

    function ActionManager(){
    }

    function execute(string32 actionName, bytes data) constant returns (bool) {
        address actionDb = ContractProvider(DOUG).contracts("actiondb");
        if (actionDb == 0x0){
            return false;
        }
        address actn = ActionDb(actionDb).actions(actionName);
        // If no action with the given name exists - cancel.
        if (actn == 0x0){
            return false;
        }
        // Set this as the currently active action.
        activeAction = actn;
        // Run the action. Any contract that calls 'validate' now will only get 'true' if the 
        // calling contract is 'actn'.
        bool b = actn.call(data);
        // Now clear it.
        activeAction = 0x0;
        return b;
    }

    function addAction(string32 name, address addr) constant returns (bool) {
        address actionDb = ContractProvider(DOUG).contracts("actiondb");
        if (actionDb == 0x0){
            return false;
        }
        bool res = ActionDb(actionDb).addAction(name,addr);
        return res;
    }

    function removeAction(string32 name) constant returns (bool) {
        address actionDb = ContractProvider(DOUG).contracts("actiondb");
        if (actionDb == 0x0){
            return false;
        }
        bool res = ActionDb(actionDb).removeAction(name);
        return res;
    }

    // Validate can be called by a contract like the bank to check if the
    // contract calling it has permissions to do so.
    function validate(address addr) constant returns (bool) {
        return addr == activeAction;
    }   

}

// The action manager. We don't enable for action manager since validating is a lot easier here.
contract ActionManager is DougEnabled {
	
        
	function execute(string32 actionName, uint8 paramLength, array params) constant return (bool result) {
		address actn = actions[actionName];
		// If no action with the given name exists - cancel.
		if (actn == 0x0){
			return false;
		}
		// Set this as the currently active action.
		activeAction = actn;
		// Run the action. Any contract that calls 'validate' now will only get 'true' if the 
		// calling contract is 'actn'.
		bool b = Action(actn).execute(params);
		// Now clear it.
		activeAction = 0x0;
		return b;
	}

	function addAction(string32 name, address addr) {
		// Make sure that the caller is the active action.
		if (msg.sender != activeAction){
			return;
		}
		DougEnabled de = DougEnabled(addr);
		if(!de.setDougAddress(this)) 
			return false;
		actions[name] = addr;
		
	}

	function removeAction(string32 name) constant return (bool result) {
		// Make sure that the action exists and that the caller is the active action.
		if (actions[name] == 0x0 || msg.sender != activeAction){
			return false;
		}
		actions[name] = 0x0;
		return true;
	}

	// We need this now too.
	function getAction(string32 name) return (address addr) {
		return actions[name]
	}

	// Validate can be called by a contract like the bank to check if the
	// contract calling it has permissions to do so.
	function validate(address addr) constant return (bool result) {
		return (addr == activeAction);
	}	

}
```

Bank
``` javascript
// The Bank contract - now inherits ActionManagerEnabled
contract Bank is ActionManagerEnabled {
	
	// This is where we keep all the permissions.
	mapping (address => uint) balance;

	// Endow an address with coins.        
	function endow(address addr, uint amount) onlyactions {
		if (!callerIsAction){
			return;
		}		
		balance[addr] += amount;
	}

	// Charge an account 'amount' number of coins.
	function charge(address addr, uint amount) constant return (bool result) onlyactions {
		if (!callerIsAction){
			return false;
		}
		if (balance[addr] < amount){
			return false;
		}

		balance[addr] -= amount;
		return true;
	}

}
```

Permissions
``` javascript
// The Permissions contract - now inherits ActionManagerEnabled
contract Permissions is ActionManagerEnabled {
	
	// This is where we keep all the permissions.
	mapping (address => uint8) perms;
        
	function setPermission(address addr, uint8 perm) onlyactions {
		if (!callerIsAction){
			return;
		}
		address charger = dg.getContract("bank");
		perms[addr] = addr;
	}

	// This does not update the contract, so no security check is needed. It's just a getter.
	function getPermission(address addr) constant return (uint permVal) {
		return perms[addr];
	}
	
}
```

Actions:

Action base
``` javascript

// Base contract for actions - note that 'execute' is not added right now because of the types and arrays stuff.
contract Action is ActionManagerEnabled {
	uint8 permReq
	
	function getPremission() constant returns (uint pLevel) {
		return permReq
	}

	function setPermission(uint8 permVal) constant returns (bool ret) onlyactions {
		if (!callerIsAction){
			return false;
		}
		permReq = permVal;
		return true;
	}

	// This is where the execute function will be.

}
```

AddAction
``` javascript

// The add action action.
contract ActionAddAction is Action {

	// Adds the action with the given name and contract address.
	function execute(string32 nameArg, string32 addressArg) constant return (bool result) {
		if(!callerIsActions){
			return false;
		}
		ContractProvider dg = ContractProvider(DOUG);
		ActionRegistry(dg.getContract("actions")).addAction(nameArg,address(addressArg));
		return true;
	}
}
```

RemoveAction
``` javascript

// The remove action action.
contract ActionAddAction is Action {

	// Removes the action with the given name.
	function execute(string32 nameArg) constant return (bool result) {
		if(!callerIsActions){
			return false;
		}
		ContractProvider dg = ContractProvider(DOUG);
		ActionRegistry(dg.getContract("actions")).removeAction(nameArg);
		return true;
	}
}
```

AddContract
``` javascript

// The add contract action.
contract ActionAddContract is Action {

	// Adds the contract with the given name and contract address to Doug.
	function execute(string32 nameArg, string32 addressArg) constant return (bool result) {
		if(!callerIsActions){
			return false;
		}
		ContractProvider dg = ContractProvider(DOUG).addContract(nameArg,address(addressArg));
		return true;
	}
}
```

RemoveContract
``` javascript

// The remove contract action.
contract ActionRemoveContract is Action {

	// Removes the contract with the given name from Doug.
	function execute(string32 nameArg) constant return (bool result) {
		if(!callerIsActions){
			return false;
		}
		ContractProvider dg = ContractProvider(DOUG).removeContract(nameArg);
		return true;
	}
}
```

SetPermission
``` javascript

// The set permission action.
contract ActionSetPermission is Action {

	// Sets the permission of the given account to the given level.
	function execute(string32 addressArg, string32 permLvl) constant return (bool result) {
		if(!callerIsActions){
			return false;
		}
		ContractProvider dg = ContractProvider(DOUG);
		address perm = dg.getContract("perms");
		PermissionSetter(perm).setPermission(address(addressArg),uint8(permLvl));
		return true;
	}
}
```

ModActionPermission
``` javascript

// The modify action permission action.
contract ActionModActionPermission is Action {

	// Sets the permission of the given action to the given level.
	function execute(string32 nameArg, string32 permLvl) constant return (bool result) {
		if(!callerIsActions){
			return false;
		}
		ContractProvider dg = ContractProvider(DOUG);
		ActionRegistry ar = ActionRegistry(dg.getContract("actions"));
		address aAddr = ar.getAction(nameArg);
		if (aAddr == 0x0) {
			return false;
		}
		Action(aAddr).setPermission(uint8(permLvl));
		return true;
	}
}
```

ActionEndow
``` javascript

// The endow action.
contract ActionEndow {

	// Endows an account with coins.
	function execute(string32 addressArg, string32 amountArg) constant return (bool result) {
		if(!callerIsActions){
			return false;
		}
		ContractProvider dg = ContractProvider(DOUG);
		address endower = dg.getContract("bank");
		// address and uint casts just placeholders.
		Endower(endower).endow(address(addressArg), uint(amountArg));
		return true;
	}
}
```

ActionCharge
``` javascript

// The charge action.
contract ActionCharge {

	// Charges an account.
	function execute(string32 addressArg, string32 amountArg) constant return (bool result) {
		if(!callerIsActions){
			return false;
		}
		ContractProvider dg = ContractProvider(DOUG);
		address charger = dg.getContract("bank");
		// address and uint casts just placeholders.
		Charger(charger).charge(address(addressArg), uint(amountArg));
		// We don't care whether or not the action succeded atm.
		return true;
	}
}
```
