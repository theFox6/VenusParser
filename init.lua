local parser = {}

local elements = {
  names = "^(%a%w*)$",
  spaces = "(%s+)",
  special = "[%%%(%)%{%}%;%,]",
  strings = "[\"']",
  special_combined = "([%+%-%*/%^#=~<>%[%]:%.][%+%-/#=>%[%]:%.]?[%.]?)",
  lambda_args = "[,%(%)]"
}

--FIXME: do not parse in single line comments

function parser.warn(msg)
  print("VenusParser warning: " .. msg)
end

--FIXME: allow multiple paterns
local function optmatch(str,pat)
  local cutstr = str
  return function()
    if not cutstr then return end
    local spos,epos = cutstr:find(pat)
    local match
    local found = (spos == 1)
    if found then
      match =  cutstr:sub(spos,epos)
      cutstr = cutstr:sub(epos+1)
      --print("f",match,cutstr,pat)
    elseif not spos then
      match = cutstr
      cutstr = nil
      --print("n",match,pat)
    else
      match = cutstr:sub(1,spos-1)
      cutstr = cutstr:sub(spos)
      --print("p",match,cutstr,pat)
    end
    return match, found
  end
end

function parser.test_optmatch()
  assert(optmatch("123","123")() == "123")
  assert(optmatch("123","321")() == "123")
  assert(optmatch("123","1")() == "1")
  assert(optmatch("123","2")() == "1")
end

--TODO: make some functions handling each group of commands
local function parse_element(el,pc)
  if el == "" then
    return el
  end
  local prefix
  if el == "elseif" then
    if pc.ifend then
      pc.ifend = false
    end
    pc.curlyopt = "if"
  elseif el == "else" then
    pc.ifend = false
    pc.curlyopt = true
    pc.precurly = el
  elseif pc.ifend then
    prefix = pc.ifend
    pc.ifend = false
  end
  
  if pc.deccheck then
    local cpos = pc.deccheck
    pc.deccheck = false
    pc.optassign = false
    if cpos == true then
      return "--"..el
    else
      return "--"..cpos..el
    end
  end
  
  if el == "=>" then
    if not pc.lambargs then
      parser.warn(("invalid lambda in line %i"):format(pc.line))
      return el
    end
    local larg = pc.lambargs
    pc.lambargs = false
    pc.lambend = false
    pc.precurly = "function"
    pc.curlyopt = true
    return "function" .. larg .. " "
  elseif pc.lambend then
    if prefix then
      parser.warn(("end statement and lambda match end may be mixed in line %i"):format(pc.line))
      prefix = pc.lambargs .. prefix
    else
      prefix = pc.lambargs
    end
    pc.lambargs = false
    pc.lambend = false
  end
  
  if el == '"' or el == "'" then
    if not pc.instring then
      pc.instring = el
    elseif pc.instring == el then
      pc.instring = false
    end
  elseif el == "[[" then
    if not pc.instring then
      pc.instring = el
    end
  elseif el == "]]" then
    if pc.instring == "[[" then
      pc.instring = false
    end
  elseif pc.instring then
    return el,prefix
  end

  if pc.foreach == 2 then
    pc.foreach = 3
    if el == "{" then
      table.insert(pc.opencurly, "table")
    end
    return "pairs("..el,prefix
  elseif el == "{" then
    if pc.foreach == 3 then
      pc.foreach = 0
      table.insert(pc.opencurly, "for")
      pc.curlyopt = false
      return ") do",prefix
    elseif not pc.curlyopt then
      if pc.linestart then
        table.insert(pc.opencurly, "do")
        return "do ",prefix
      else
        table.insert(pc.opencurly, "table")
        return el,prefix
      end
    elseif pc.curlyopt == true then
      if pc.precurly == "function" or pc.precurly == "repeat" or pc.precurly == "else" then
        table.insert(pc.opencurly, pc.precurly)
        pc.precurly = false
        pc.curlyopt = false
        return "",prefix
      end
    elseif pc.curlyopt == "for" or pc.curlyopt == "while" then
      table.insert(pc.opencurly, pc.curlyopt)
      pc.curlyopt = false
      return " do",prefix
    elseif pc.curlyopt == "if" then
      table.insert(pc.opencurly, pc.curlyopt)
      pc.curlyopt = false
      return " then",prefix
    end
  elseif pc.precurly then
    pc.precurly = false
    pc.curlyopt = false
  end

  if el == "}" then
    local closecurly = table.remove(pc.opencurly)
    if closecurly == "table" then
      return el,prefix
    elseif closecurly == "repeat" then
      return "",prefix
    elseif closecurly == "for" or closecurly == "while" or
        closecurly == "function" or closecurly == "repeat" or
        closecurly == "do" or closecurly == "else" then
      return "end",prefix
    elseif closecurly == "if" then
      pc.ifend = "end"
      return "",prefix
    else
      parser.warn(("closing curly bracket in line %i could not be matched to an opening one"):format(pc.line))
      return el,prefix
    end
  elseif el == "foreach" then
    pc.curlyopt = "for"
    pc.foreach = 1
    return "for _,",prefix
  elseif el == "for" then
    pc.curlyopt = el
    pc.foreach = 0
  elseif el == "in" then
    if pc.foreach == 1 then
      pc.foreach = 2
    end
  elseif el == "do" then
    pc.curlyopt = false
    if pc.foreach == 3 then
      pc.foreach = 0
      return ") " .. el,prefix
    end
  elseif el == "while" then
    pc.curlyopt = el
  elseif el == "repeat" then
    pc.precurly = el
    pc.curlyopt = true
  elseif el == "if" then
    pc.curlyopt = el
  elseif el == "then" then
    pc.curlyopt = false
  elseif el == "fn" then
    pc.curlyopt = "function"
    return "function",prefix
  elseif el == "function" then
    pc.curlyopt = el
  elseif el == "(" then
    pc.newlamb = el
    pc.lambend = false
    return "",prefix
  elseif el == ")" then
    if pc.curlyopt == "function" then
      pc.precurly = pc.curlyopt
      pc.curlyopt = true
    end
    if pc.lambargs then
      pc.lambend = true
    end
  elseif el == "//" or el=="##" then
    if not pc.instring then
      return "--",prefix
    end
  elseif el == "--" then
    if pc.optassign then
      pc.deccheck = true
      return "",prefix
    else
      return el,prefix
    end
  elseif el == "++" then
    if pc.optassign then
      local nam = pc.optassign
      pc.optassign = false
      return " = " .. nam .. " + 1"
    else
      parser.warn(("empty increment in line %i"):format(pc.line))
      return el, prefix
    end
  end
  --print(el,pc.instring and "in string" or "")
  return el, prefix
end

--TODO: make functions handling the lambdas
local function parse_line(l,pc)
  local pl = ""
  local i = 0
  for sp,s in optmatch(l,elements.spaces) do
    if s then
      if pc.lambargs then
        pc.lambargs = pc.lambargs .. sp
      elseif pc.deccheck then
        if pc.deccheck == true then
          pc.deccheck = sp
        else
          pc.deccheck = pc.deccheck .. sp
        end
      else
        pl = pl .. sp
      end
      if pc.optassign then
        if pc.optassign ~= true then
          pc.optassign = pc.optassign .. sp
        end
      end
    else
      for sc in optmatch(sp,elements.special_combined) do
      for ss in optmatch(sc,elements.special) do
      for st in optmatch(ss,elements.strings) do
        local el,pre = parse_element(st,pc)
        local lpre
        if pre then
          while pre:match("\n") do
            if lpre then
              lpre = lpre .. pre:sub(1,pre:find("\n"))
            else
              lpre = pre:sub(1,pre:find("\n"))
            end
            pre = pre:sub(pre:find("\n")+1)
          end
          local pres = pre:match("^%s*") or ""
          if lpre then
            lpre = lpre .. pres
          else
            lpre = pres
          end
          pre = pre:sub(#pres+1)
          --[[
          if (pre ~= "") then
            print("pre:".. pre..":")
          else
            print("prel:" .. el)
          end
          --]]
          if el == "" then
            el = pre
          elseif pre ~= "" then
            el = pre .. " " .. el
          end
        end
        if pc.newlamb then
          if pc.lambargs then
            el = pc.lambargs .. el
          end
          pc.lambargs = pc.newlamb
          pc.newlamb = false
          --print("newl:", pc.lambargs, el)
        elseif pc.lambargs then
          if el:match(elements.names) or el:match(elements.lambda_args) then
            pc.lambargs = pc.lambargs .. el
            el = ""
          elseif el ~= "" then
            el = pc.lambargs .. el
            pc.lambargs = false
            pc.lambend = false
            --print("notl:", el)
          end
        end
        if pc.optassign and el ~= "" then
          if pc.linestart and el:match(elements.names) then
            if pc.optassign == true then
              pc.optassign = el
            else
              pc.optassign = pc.optassign .. el
            end
          elseif el ~= "--" then
            pc.optassign = false
          end
        end
        if lpre then
          pl = pl .. lpre .. el
        else
          pl = pl .. el
        end
        if pc.linestart then
          pc.linestart = false
        end
      end
      end
      end
    end
  end
  return pl
end

--TODO: make functions handling the ifend and lambargs
function parser.translate_venus(file)
  local fc = ""
  local pc = {instring = false, opencurly = {}, line = 0}
  for l in io.lines(file) do
    pc.line = pc.line + 1
    pc.linestart = true
    pc.optassign = true
    fc = fc .. parse_line(l,pc)
    if pc.ifend then
      if pc.linestart then
        fc = fc .. pc.ifend
      else
        fc = fc .. " " .. pc.ifend
      end
      pc.ifend = false
    end
    if pc.deccheck then
      if pc.optassign == false then
        pc.deccheck = false
      elseif pc.optassign == true then
        pc.deccheck = false
      else
        fc = fc .. " = " .. pc.optassign .. " - 1"
        pc.deccheck = false
        pc.optassign = false
      end
    end
    if pc.lambargs then
      pc.lambargs = pc.lambargs .. "\n"
    else
      fc = fc .. "\n"
    end
  end
  if (#pc.opencurly > 0) then
    parser.warn("not all curly brackets were closed")
  end
  return fc
end

function parser.loadvenus(file,env)
  local fc = parser.translate_venus(file)
  if env then
    return loadstring(fc,"@"..file,"t",env)
  else
    return loadstring(fc,"@"..file)
  end
end

function parser.dovenus(file)
  local ff, err = parser.loadvenus(file)
  if ff == nil then
    error(err,2)
  end
  return ff()
end

-- in case anybody wants to use it too
parser.optmatch = optmatch

return parser
