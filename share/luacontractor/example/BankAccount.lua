
--[[
This is the classical Design by Contract example of
a bank account model
]]

require "contractor"
local ct = contractor

--[[
First, we make a few objects: a bank and an account
]]
local function makeBank(name,agency)
  bank = { tag="Bank", name=name, agency=agency, accounts={} }
  return bank
end

local function makeBankAccount(bank,firstname,lastname)
  -- global
  account = { tag="Account", bank=bank,firstname=firstname, lastname=lastname,
              id=#bank.accounts, balance=0 }
  account.deposit = function(accnt,amount)
    accnt.balance = accnt.balance + amount
  end
  account.withdraw = function(accnt,amount)
    accnt.balance = accnt.balance - amount
  end
  table.insert(bank.accounts,account)
  accountMT = {}
  accountMT.__tostring = function(accnt)
    return "{ [Account ID:" .. tostring(accnt.id) .. "] " .. accnt.firstname .. " " .. accnt.lastname .. ": " 
              .. "balance = " .. tostring(accnt.balance) .. " euros }"    
  end
  setmetatable(account,accountMT)
  return account
end

-- let's create a given bank
local bank = makeBank("Bank of Tokyo","Paris")

-- and of course our account
print("Create account:")
local account = makeBankAccount(bank,"Freddy", "Peschy")
print(tostring(account))

-- put some money at first
print("Deposit 100:")
account:deposit(100) -- euros ?
print(tostring(account))

print("Withraw 50:")
account:withdraw(50)
print(tostring(account))

-- some things we would like to avoid
print("Deposit -10 (oops?!):")
account:deposit(-10)
print(tostring(account))

print("Withdraw -10 (oops?!):")
account:withdraw(-10)
print(tostring(account))

-- now install the contracts for deposit

account.deposit = ct.addPrecondition(account.deposit,
  function(contract,account,amount)
    local ok, msg = contract:check(amount>0,"Must deposit a strictly positive amount of money, given " .. tostring(amount))
    if ok then
      contract:capture("balance@pre",account.balance)
      return ok
    else
      return ok, msg
    end
  end)
  
account.deposit = ct.addPostcondition(account.deposit,
  function(contract,account,amount)
    return contract:check(account.balance == contract.captures["balance@pre"] + amount, 
                          "The balance is wrong ")
  end)
  
print("Deposit 10:")
account:deposit(10)
print(tostring(account))

print("Deposit -10 (oops?!):")
local ok,msg = pcall(account.deposit,account,-10)
if not ok then
  print(msg)
end
print(tostring(account))

-- now let's try to use a buggy deposit function

account.badDeposit = function(accnt,amount)
  accnt.balance = accnt.balance - amount
end

account.badDeposit = ct.addPrecondition(account.badDeposit,
  function(contract,account,amount)
    local ok, msg = contract:check(amount>0,"Must deposit a strictly positive amount of money, given " .. tostring(amount))
    if ok then
      contract:capture("balance@pre",account.balance)
      return ok
    else
      return ok, msg
    end
  end)

account.badDeposit = ct.addPostcondition(account.badDeposit,
  function(contract,account,amount)
    return contract:check(account.balance == contract.captures["balance@pre"] + amount, 
                          "The balance is wrong ")
  end)

print("(bad) Deposit 10 :")
local ok,msg = pcall(account.badDeposit,account,10)
if not ok then
  print(msg)
end
print(tostring(account))

-- let's remove this bad method
account.badDeposit = nil

-- check for withdraw

account.withdraw = ct.addPrecondition(account.withdraw,
  function(contract,account,amount)
    local ok, msg = contract:check(amount>0,"Must withdraw a strictly positive amount of money, given " .. tostring(amount))
    if not ok then
      return ok,msg
    end
    contract:capture("balance@pre",account.balance)
    return ok
  end)
  
account.withdraw = ct.addPostcondition(account.withdraw,
  function(contract,account,amount)
    return contract:check(account.balance == contract.captures["balance@pre"] - amount, 
                          "The balance is wrong ")
  end)

print("Withdraw 10:")
account:withdraw(10)
print(tostring(account))

print("Withdraw -10 (oops?!):")
local ok,msg = pcall(account.withdraw,account,-10)
if not ok then
  print(msg)
end
print(tostring(account))

-- finally, we would like to avoid the following

print("Withdraw 50:")
account:withdraw(50)
print(tostring(account))

-- we will use an invariant
-- let's fill again the account
print("Deposit 50:")
account:deposit(50)
print(tostring(account))

-- install a new invariant
account = ct.addInvariant(account,
  function(contract,accnt)
    return contract:check(accnt.balance>=0,"The balance must be positive")
  end)
  
print("Withdraw 50:")
local ok, msg = pcall(account.withdraw,account,50)
if not ok then
  print(msg)
end
print(tostring(account))

-- another solution is to protect the withdraw method (defensive approach)
account.withdraw = ct.addPrecondition(account.withdraw,
  function(contract,account,amount)
    local ok, msg = contract:check(amount<=account.balance,"Must withdraw at most the balance")
    if not ok then
      return ok,msg
    end
    contract:capture("balance@pre",account.balance)
    return ok
  end)

print("Withdraw 50:")
local ok, msg = pcall(account.withdraw,account,50)
if not ok then
  print(msg)
end
print(tostring(account))

-- now let's remove the method contracts
account.deposit = ct.unwrapFunction(account.deposit)
account.withdraw = ct.unwrapFunction(account.withdraw)

print("Deposit -10 (oops?!):")
account:deposit(-10)
print(tostring(account))

print("Withdraw -10 (oops?!):")
account:withdraw(-10)
print(tostring(account))

-- note that the invariant contract is still active
print("Withdraw 50:")
local ok, msg = pcall(account.withdraw,account,50)
if not ok then
  print(msg)
end
print(tostring(account))

-- and let's remove it
account = ct.unwrapTable(account)

-- and the program goes bag to "buggy mode"
-- but there is no wrapper at all anymore
print("Withdraw 50:")
account:withdraw(50)
print(tostring(account))
