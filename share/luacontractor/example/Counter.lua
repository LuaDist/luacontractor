-- a simple test of a counter function

require "contractor"

local ct = contractor

--[[
In the first part we demonstrate the functional contracts.

A functional contract wraps a function with a set of preconditions
and postconditions. When wrapped, the preconditions are called at first.
This possibly raises an error an stops the program if a precondition has
failed (one may use pcall to get the error without stopping the program)
In the second step, the wrapped function itself is called.
And finally the postconditons are checked.

Here we take a simple counter variable example
]]

local counter = 0

-- a function to increases the value of a counter
function addCounter(val)
  counter = counter + val
  print("Counter is",counter)
end

--[[
Here we define a precondition for the addCounterFunction.
This always take a contract table as well as the set of arguments
used to call the function (here, just one argument)

The contract:check method is used to check a boolean property. Its
use is similar to the assert function of Lua.

The contract:capture method allows to save the value of some variable
before the wrapped function is executed. Here we save the value of the
counter.
]]
function addCounterPre(contract,val)
  local test,message = contract:check(val>0,"val should be >0, given "..tostring(val))
  if not test then
    return test,message
  end
  contract:capture("counter",counter)
  return true
end

-- the following is a postcondition that checks if the counter has been increased as needed
function addCounterPost(contract,val)
  local test,message = contract:check(counter==contract.captures["counter"]+val,"counter should be counter+val (="..tostring(counter+val)..") found "..tostring(counter))
  if not test then
    return test,message
  end
  return true
end

-- first try without contracts
print("Counter is initially",counter)
addCounter(4)
addCounter(-4)

-- add conditions
addCounter = ct.addPrecondition(addCounter,addCounterPre)
addCounter = ct.addPostcondition(addCounter,addCounterPost)

-- second try with contracts
addCounter(4)
local ok,message = pcall(addCounter,-4)
print(message)

-- remove contract
addCounter = ct.unwrapFunction(addCounter)

-- finally we try again without contracts
addCounter(4)
addCounter(-8)

--[[
In the second part we see the table contracts.
A table that is wrapped with a contract can enforce invariants
on the values in the table.
]]

local counter = { tag="counter", value=0 }

print("value=",counter.value)

function changeCounter(val)
  counter.value = counter.value + val
  print("Counter is",counter.value)
end

-- without a contract
changeCounter(4)
changeCounter(-5)
changeCounter(1)

--[[
Now we add an invariant. An invariant function takes a contract
variable (with a single check method) and then the wrapped table as its 
second parameter
]]
function counterInv(contract,tabl)
  --print("calling 'counterInv' invariant")
  return contract:check(tabl.value>=0,"the counter should be positive, found "..tostring(tabl.value))
end

-- wrap the table
counter = ct.addInvariant(counter,counterInv)

-- with the contract
changeCounter(4)
local ok, message = pcall(changeCounter,-5)
if not ok then
  print(message)
end

-- the counter should have gone back to 4
changeCounter(-4)
-- so now it should be 0
assert(counter.value==0)
