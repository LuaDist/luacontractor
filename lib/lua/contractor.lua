
module(...,package.seeall);

-- This is a first try to implement a generic design by contract package for Lua
-- This is also a way to play with Lua and work with the closures and metatable
-- features

-- the main datastructure to save the functional contracts
local FunctionalContracts = {}
local FunctionalContractsMT = { __tostring = functionalContractsToString }
setmetatable(FunctionalContracts,FunctionalContractsMT)

-- pretty printer for individual contracts
function functionalContractToString(contract)
  local str = "{ "
  str = str.."pre={"
  for i,v in ipairs(contract.pre) do
    str = str..tostring(v)
    if i<#contract.pre then
      str = str..","
    end
  end
  str = str.."},post={"
  for i,v in ipairs(contract.post) do
    str = str..tostring(v)
    if i<#contract.post then
      str = str..","
    end
  end
  str = str.."},base="..tostring(contract.base)..",wrap="..tostring(contract.wrapper).." }"
  return str
end

-- pretty printer for global contract structure
function functionalContractsToString(contracts)
  str = "{ \n"
  for k,v in pairs(contracts) do
    if k~=v then
      str = str.."  "..tostring(k).."="..functionalContractToString(v).."\n"
    else
      str = str.."  "..tostring(k).." [wrapper]\n"
    end
  end
  str = str.."}\n"
  return str
end

-- the global wrapping function
function buildFunctionalWrapper(fun)
  if FunctionalContracts[fun]==nil then
    -- not an already wrapped function
    local contract = { tag = "fcontract", pre = {}, post = {}, captures = {}, base=fun }
    local FunctionalContractMT = { __tostring = functionalContractToString }
    setmetatable(contract,FunctionalContractMT)
    
    FunctionalContracts[fun] = contract
    local wrapper = function(...)
      --print("Function wrapper called with args=",...)
      -- 1) test preconditions
      if next(contract.pre)~=nil then
        for i,cond in ipairs(contract.pre) do 
           local res,message = cond(contract,...)
           if not res then
             error("Precondition failure:\n  ==> "..message.."\n",3) -- caller error
           end -- if
        end -- for
      end --if
      -- 2) treatment
      ret = contract.base(...)
      -- 3) test postconditions
      if next(contract.post)~=nil then
        for i,cond in ipairs(contract.post) do 
           local res,message = cond(contract,...)
           if not res then
             error("Postcondition failure:\n  ==> "..message.."\n",3) -- caller error
           end -- if
        end -- for
      end -- if
      -- 4) erase the captures
      eraseCaptures(contract)
      return ret
    end -- wrapper function
    contract.wrapper = wrapper
    contract.capture = captureVariable
    contract.check = checkCondition
    -- register the wrapper so that it may not be wrapped itself
    FunctionalContracts[wrapper] = contract
    return fun,wrapper
  elseif FunctionalContracts[fun]~=nil then
    return fun,FunctionalContracts[fun].wrapper
  end
end

-- would really enjoy define-syntax here ...
function checkCondition(contract,cond,message)
  if not cond then
    return cond,message
  else
    return true
  end
end

-- variable captures
function captureVariable(contract,varname,value)
  if contract.captures==nil then
    contract.captures = {}
  end
  contract.captures[varname] = value
end

-- GC the captures
function eraseCaptures(contract)
  contract.captures = nil
end

-- main function to add a precondition
-- one may of course add multiple preconditions
-- they will be checked in the order of registration
function addPrecondition(fun,pre)
  if type(fun)~="function" then
    error("Precondition only apply to functions")
  end
  if type(pre)~="function" then
    error("Precondition must be a function")
  end
  local base,wrapper = buildFunctionalWrapper(fun)
  --print("addPre: fun",fun,"base",base,"wrapper",wrapper)
  table.insert(FunctionalContracts[fun].pre,pre)
  --print("addPre: contract = "..tostring(FunctionalContracts[base]))
  return wrapper
end

-- to remove all preconditions
function clearPreconditions(fun)
  local base,wrapper = buildFunctionalWrapper(fun)
  FunctionalContracts[base].pre = {}
end

-- registering post-conditions
function addPostcondition(fun,post)
  if type(fun)~="function" then
    error("Postconditions only apply to functions")
  end
  if type(post)~="function" then
    error("Postcondition must be a function")
  end
  local base,wrapper = buildFunctionalWrapper(fun)
  --print("addPost: fun",fun,"base",base,"wrapper",wrapper)
  table.insert(FunctionalContracts[base].post,post)
  --print("addPost: contract = "..tostring(FunctionalContracts[base]))
  return wrapper
end

-- removing them
function clearPostconditions(fun)
  local base,wrapper = buildFunctionalWrapper(fun)
  FunctionalContracts[base].post = {}
end

-- this function removes the functional contract wrapper
-- so we get the real function
function unwrapFunction(fun)
  if FunctionalContracts[fun]==fun then
    return fun -- not a wrapped function but a wrapper => return itself
  elseif FunctionalContracts[fun]~=nil then
    -- that's a wrapped function
    local contract = FunctionalContracts[fun]
    local wrapper = contract.wrapper
    FunctionalContracts[wrapper] = nil
    FunctionalContracts[fun] = nil
    return contract.base
  else -- a normal (non-wrapped function): just return itself
    return fun
  end
end

-- wrappers for table contracts (invariants)

-- the wrapping function
function buildTableWrapper(tabl)
  --print("Wrapping table",tabl)
  tablWrapper = { tag="tcontract", delegate=tabl, inv = { inv } }
  local tablWMT = getmetatable(tabl) -- install metamethods in delegate
  -- metamethod : ttable[key] = val
  if tablWMT==nil then
    tablWMT = {}
  end
  tablWrapper.oldNewIndex = tablWMT.__newindex
  tablWMT.__newindex = function(ttabl,key,val)
    --print("Assignment to table",ttabl,"for key",key,"and value",val)
    local oldval = ttabl.delegate[key]
    -- if new index metamethod was installed, delegate to it
    -- Remark: this can not be reversed by the wrapper
    if tablWrapper.oldNewIndex~=nil then
      tablWrapper.oldNewIndex(ttabl.delegate,key,val)
    else
      ttabl.delegate[key] = val
    end
    local contract = { check = checkCondition }
    for i,invfun in ipairs(ttabl.inv) do
      local test, message = invfun(contract,ttabl.delegate)
      --print("Invariant test is",test)
      --print("Invariant message is",message)
      if not test then
        ttabl.delegate[key] = oldval
        error("Invariant failure:\n  ==> "..message.."\n",2) -- caller error
      end
    end
  end
  -- metamethod: ttabl[key]
  tablWrapper.oldIndex = tablWMT.__index
  --print("old index =",tablWrapper.oldIndex)
  tablWMT.__index = function(ttabl,key)
    --print("indexing key",tostring(key))
    local val = rawget(ttabl,key)
    --print("fetch val",val)
    if val~=nil then
      return val
    end
    --print("old index = ",tostring(rawget(ttabl,oldIndex)))
    if rawget(ttabl,oldIndex)~=nil then
      --print("calling old index")
      return rawget(ttabl,oldIndex)(rawget(ttabl,"delegate"),key)
    else
      --print("Accessing",key,"on delegate",rawget(ttabl,"delegate"))
      if rawget(ttabl,"delegate") ~= nil then
        local val = rawget(ttabl,"delegate")[key]
        --print("Accessed value is",val)
        return val
      else
        return nil
      end
    end
  end
  -- install the metatable
  setmetatable(tablWrapper,tablWMT)
  return tablWrapper
end

-- we can add multiple invariants
-- an invariant is a function that takes
-- the contract and the contracted table
-- as arguments. It must return a flag
-- value and an optional error message
function addInvariant(tabl,inv)
  if type(table)~="table" then
    error("Invariants only apply on tables")
  end
  if type(inv)~="function" then
    error("Invariant must be a function")
  end
  local wrap = tabl
  if table.tag~="tcontract" then
    wrap = buildTableWrapper(tabl)
  end
  table.insert(wrap.inv,inv)
  return wrap
end

-- remove all invariants
function clearInvariants(tabl)
  if type(table)~="table" or table.tag~="tcontract" then
    error("Can only remove invariants from contracted table")
  end
  tabl.inv = {}
end

-- remove the table contract wrapper
-- so we get back the real table
function unwrapTable(tabl)
  if type(table)~="table" or tabl.tag~="tcontract" then
    error("Can only unwrap a contracted table")
  end
  tablMT = getmetatable(tabl)
  tablMT.__newindex = tabl.oldNewIndex
  tablMT.__index = tabl.oldIndex
  delegate = tabl.delegate
  setmetatable(delegate,tablMT)
  tabl = {} -- no need for the wrapper any more
  return delegate
end
