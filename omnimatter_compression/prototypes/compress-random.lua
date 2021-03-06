----log(serpent.block(random_recipes))

local exclusion_list = {"void","flaring","incineration"}

local check_recipes = random_recipes

local top_value = 500
local roundRndValues = {}
local b,c,d = math.log(5),math.log(3),math.log(2)
for i=0,math.floor(math.log(top_value)/b) do
  local pow5 = math.pow(5,i)
  for j=0,math.floor(math.log(top_value/pow5)/c) do
    local pow3=math.pow(3,j)
    for k=0,math.floor(math.log(top_value/pow5/pow3)/d) do
      roundRndValues[#roundRndValues+1] = pow5*pow3*math.pow(2,k)
    end
  end
end
table.sort(roundRndValues)

local roundRandom = function(nr,round)
  local t = omni.lib.round(nr)
  local newval = t
  for i=1,#roundRndValues-1 do
    if roundRndValues[i]< t and roundRndValues[i+1]>t then
      if t-roundRndValues[i] < roundRndValues[i+1]-t then
        local c = 0
        if roundRndValues[i] ~= t and round == 1 then c=1 end
        newval = roundRndValues[i+c]
      else
        local c = 0
        if roundRndValues[i+1] ~= t and round == -1 then c=-1 end
        newval = roundRndValues[i+1+c]
      end
    end
  end
  return math.max(newval,1)
end
log("start probability style compression")

for _,recipe in pairs(check_recipes) do
  if not omni.lib.is_in_table(recipe,exclusion_list) and not string.find(recipe,"creative") then
    local double = false
    --local store = data.raw.recipe[recipe]
    local rec = table.deepcopy(data.raw.recipe[recipe])
    --grab localisation before standardisation
    local loc = omni.lib.locale.custom_name(data.raw.recipe[recipe], "compressed-recipe")
    --standardise
    if not mods["omnimatter_marathon"] then omni.lib.standardise(rec) end
    --double check shenanigans are not happening
    rec.ingredients=nil
    rec.ingredient=nil
    rec.result=nil
    rec.results=nil
    local prob = {normal={},expensive={}}
    --prob table should include more details than just the number, the order of items seems to get changed in create_compression_recipes
    for _,dif in pairs({"normal","expensive"}) do
      for i,res in pairs(rec[dif].results) do
        --check item not already in table
        nme = res.name
        if prob[dif][res.name] then
          --already exists, give new one a fresh tag
          nme=res.name .."-p"
        end
        --begin property setting, bring name into the key
        prob[dif][nme]={style="normal"}
        if res.amount_min and res.amount_max and res.amount_max <= res.amount_min then
          res.amount = res.amount_min
          res.amount_min = nil
          res.amount_max = nil
        end
        local amt = res.amount --set default value
        --amount min system
        -- "min-max" parses mininum, sets mm_prob as max/min
        -- "min-chance" parses minimum, sets mp_prob as min*prob
        -- "zero-max" parses maximum only
        -- "chance" parses average yield, sets prob as prob
        if res.amount_min and res.amount_min > 0 then
          amt = res.amount_min
          if res.amount_max then
            prob[dif][nme].style = "min-max"
            prob[dif][nme].mm_prob = res.amount_max/amt
          elseif res.probability then --don't know why you would use this, but sure...
            prob[dif][nme].style = "min-chance"
            prob[dif][nme].mp_prob = res.probability
          end
        elseif res.amount_min and res.amount_min == 0 then
          if res.amount_max then
            amt = res.amount_max
            prob[dif][nme].style = "zero-max"
          else
            log("what are you doing with".. rec.name .. "?")
          end
        elseif res.amount and res.probability then --normal style, priority over previous step
          prob[dif][nme].style = "chance"
          prob[dif][nme].prob = res.probability
          amt = math.max(roundRandom(amt*res.probability,1),1) --stop it giving 0?
        end
        --set rec
        res.amount = amt
        --prevent shenanigans
        res.amount_min=nil
        res.amount_max=nil
        res.probability=nil
      end
    end
    --parse to compression
    local new_rec = create_compression_recipe(rec)
    --add in manipulation to return the form
    if new_rec then
      local secondary = {}
      for _,dif in pairs({"normal","expensive"}) do
        for i,res in pairs(new_rec[dif].results) do
          local name = string.sub(res.name,12)
          if res.type == "fluid" then
            name = string.sub(res.name,14)
          end
          --instigate secondary
          if secondary[name]==true then
            name=name .."-p"
          end
          if prob[dif][name] then
            local prob_tab = prob[dif][name]
            local new_tab = new_rec[dif].results[i]
            --get style
            if prob_tab.style == "min-max" then
              if new_tab.amount and math.floor(new_tab.amount*prob_tab.mm_prob) > new_tab.amount then --check it actually gets a range
                new_tab.amount_min = new_tab.amount
                new_tab.amount_max = math.floor(new_tab.amount*prob_tab.mm_prob) --always round down
                new_tab.amount = nil --remove standard if min and max exist
              end
            elseif prob_tab.style == "zero-max" then
              new_tab.amount_min = 0
              new_tab.amount_max = new_tab.amount
              new_tab.amount = nil
            elseif prob_tab.style == "min-chance" then
              new_tab.amount_min = new_tab.amount
              new_tab.probability = prob_tab.mp_prob
              new_tab.amount = nil
            elseif prob_tab.style == "chance" then
              new_tab.probability = prob_tab.prob
            end
          end
          --check for double entries after primary
          if prob[dif][name .."-p"] then
            secondary[name]=true
          end
        end
      end
      new_rec.localised_name = new_rec.localised_name or loc
      data:extend({new_rec})
    else
      if not string.find(recipe,"void") then --ignore void recipes
        --log("you fucked up big time with this recipe: "..rec.name)
      end
    end
  end
end
log("end probability style compression")
