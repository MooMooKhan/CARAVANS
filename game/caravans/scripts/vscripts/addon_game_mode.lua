require('timers')
require('util')


if Caravans == nil then
	Caravans = class({})
	_G.Caravans = Caravans
end

require('neutrals')

CARAVANS_RUNES_SPAWN_COST = 4
CARAVANS_RUNES_BUYBACK_COST = 10

LinkLuaModifier("modifier_presents","modifier_presents.lua",LUA_MODIFIER_MOTION_NONE)
LinkLuaModifier("modifier_caravan","modifiers",LUA_MODIFIER_MOTION_NONE)
LinkLuaModifier("modifier_spawnpoint","modifiers",LUA_MODIFIER_MOTION_NONE)
LinkLuaModifier("modifier_frostivus_aura","modifiers",LUA_MODIFIER_MOTION_NONE)

function Precache( context )
	--[[
		Precache things we know we'll use.  Possible file types include (but not limited to):
			PrecacheResource( "model", "models/courier/donkey_trio/mesh/donkey_trio.vmdl", context )
			PrecacheResource( "soundfile", "*.vsndevts", context )
			PrecacheResource( "particle", "*.vpcf", context )
			PrecacheResource( "particle_folder", "particles/folder", context )
	]]
end

-- Create the game mode when we activate
function Activate()
	GameRules.Caravans = Caravans()
	Caravans:InitGameMode()
end

function Caravans:InitGameMode()

	self.round = 1

	self.presentsInCaravan = 25 

	self.direPresents = 0
	--self.radiantPresents = 0

	self.direPresentsTotal = 0
	self.radiantPresentsTotal = 0

	self:ClientUpdatePresents()
	self.presents = 30 
	self.presentsMin = 10
	self.presentDissappearTime = 10

	CaravanUnitTable = {}
	_G.CaravanUnitTable = CaravanUnitTable

    ListenToGameEvent("game_rules_state_change",Dynamic_Wrap(Caravans, "OnStateChange"),self)

    ListenToGameEvent("player_connect_full",Dynamic_Wrap(Caravans, "OnFullConnected"),self)
    ListenToGameEvent('player_chat', Dynamic_Wrap(Caravans, 'OnPlayerChat'), self)
    --ListenToGameEvent('dota_player_pick_hero', Dynamic_Wrap(Caravans, 'OnPlayerPickHero'), self)

    ListenToGameEvent("npc_spawned",Dynamic_Wrap(Caravans, "OnNpcSpawned"),self)
    ListenToGameEvent("entity_killed",Dynamic_Wrap(Caravans, "OnEntityKilled"),self)
    ListenToGameEvent("dota_item_picked_up",Dynamic_Wrap(Caravans, "OnItemPickedUp"),self)
  	GameRules:GetGameModeEntity():SetExecuteOrderFilter( Dynamic_Wrap( Caravans, "FilterExecuteOrder" ), self )
  	CustomGameEventManager:RegisterListener("SelectSpawnPoint", Dynamic_Wrap(Caravans, 'SelectSpawnPoint'))
  	CustomGameEventManager:RegisterListener("BuyBack", Dynamic_Wrap(Caravans, 'RunesBuyBack'))



	--GameRules:GetGameModeEntity():SetThink( "OnThink", self, "GlobalThink", 2 )

	--GameRules:SetPreGameTime(180)
	GameRules:SetPreGameTime(10)
	GameRules:LockCustomGameSetupTeamAssignment(true)
    GameRules:SetCustomGameSetupRemainingTime(0)
	GameRules:SetCustomGameSetupAutoLaunchDelay(0)



	curwp = 2
	waypoints = {}
	for i=1,25 do
		waypoints[i] = Entities:FindByName(nil,"wp"..i):GetOrigin()
	end

	Neutrals:Init()
end


function Caravans:OnEntityKilled(keys)
	local killed = EntIndexToHScript(keys.entindex_killed)

	if killed:IsRealHero() then
		Caravans:OnHeroDied(killed)
	end

	if killed.spawnPoint then
		Neutrals:OnDeath(killed)
	end

end

function Caravans:OnNpcSpawned(t)
	local spawnedentity = EntIndexToHScript(t.entindex)
	if spawnedentity:IsRealHero() then
		Caravans:OnHeroSpawned(spawnedentity)
	end
end

firstherospawned = false
function Caravans:OnHeroSpawned(hero)
	if not hero.spawned then
		hero:AddNewModifier(hero,nil,"modifier_frostivus_aura",{})
		hero.runes = 0
		hero.spawned = true
	end
	if not firstherospawned then
		Caravans:OnFirstHeroSpawn()
		firstherospawned = true
	end
	if not hero.selectedspawnpoint or hero.selectedspawnpoint == 0 then
		SpawnOnRandomTotem(hero)
	else
		SpawnOnSpawnPoint(hero)
	end
	hero.selectedspawnpoint = 0
    CustomGameEventManager:Send_ServerToPlayer(PlayerResource:GetPlayer(hero:GetPlayerOwnerID()),"HideDeathScreen",{})
end
function Caravans:OnHeroDied(hero)
    CustomGameEventManager:Send_ServerToPlayer(PlayerResource:GetPlayer(hero:GetPlayerOwnerID()),"ShowDeathScreen",{})

	for i=1,hero.presents do
		Caravans:DropPresent(hero,hero:GetAbsOrigin()+RandomVector(RandomInt(0,200)),RandomFloat(0.4,0.7))
	end

    if hero:GetTeamNumber() == DOTA_TEAM_GOODGUYS then
    	Caravans:SetDirePresents(self.direPresents + hero.presents)
    end

    hero.presents = 0
end
function Caravans:SelectSpawnPoint(t)
	local hero = PlayerResource:GetSelectedHeroEntity(t.PlayerID)
	if hero:CheckRunes(CARAVANS_RUNES_SPAWN_COST) then
		hero.selectedspawnpoint = t.number
	end
end
function Caravans:RunesBuyBack(t)
	local hero = PlayerResource:GetSelectedHeroEntity(t.PlayerID)
	if hero:CheckRunes(CARAVANS_RUNES_BUYBACK_COST) then
		hero:ModifyRunes(-CARAVANS_RUNES_BUYBACK_COST)
		hero:RespawnHero(true,false,true)
	end
end

function Caravans:DropPresent(unitFrom,posTo,dropTime,visible) 
	local item = CreateItem("item_present",nil,nil)
	local container = CreateItemOnPositionForLaunch(unitFrom:GetAbsOrigin(),item)
	item:LaunchLoot(false,RandomInt(150,300),dropTime,posTo)

	if visible == nil then
		visible = true
	end

	if visible then
		vision = function(container) 
				AddFOWViewer(DOTA_TEAM_BADGUYS,container:GetAbsOrigin(), 16, 1, false)
				AddFOWViewer(DOTA_TEAM_GOODGUYS,container:GetAbsOrigin(), 16, 1, false)
				return 0.5
			end

		container:SetContextThink("Vision",vision,0.5)
	end

	return container
end

function Caravans:CaravanAttacked(attacker,target)
	if self.presentsInCaravan > 0 then
		Caravans:DecrementCaravanPresents()
		Caravans:IncrementDirePresents()
		
		if attacker:GetRangeToUnit(target) > 300 then
			pos = target:GetAbsOrigin() 
				+ 300*(attacker:GetAbsOrigin()-target:GetAbsOrigin()):Normalized() 
				+ RandomVector(RandomInt(0,100))
		else
			pos = attacker:GetAbsOrigin() + RandomVector(RandomInt(0,100))
		end

		Caravans:DropPresent(target,pos,0.5)
	
	end
end 



function CDOTA_BaseNPC_Hero:ModifyRunes(amount)
	self.runes = self.runes + amount
    CustomGameEventManager:Send_ServerToPlayer(PlayerResource:GetPlayer(self:GetPlayerOwnerID()),"RunesUpdate",{runes = self.runes})
end
function CDOTA_BaseNPC_Hero:CheckRunes(amount)
	if self.runes > amount then
		return true
	end
	return false
end


function Caravans:OnFullConnected(event)
	
end

function Caravans:OnPlayerPickHero(event)
	local hero = EntIndexToHScript(event.heroindex)

    local heroSelected = PlayerResource:GetSelectedHeroEntity(playerID)
    
    if heroSelected then --отсеиваем иллюзии
        return
    end

end

function Caravans:OnPlayerChat(event)
	if event.text == "dire" then
		PlayerResource:GetPlayer(event.playerid):SetTeam(DOTA_TEAM_BADGUYS)
		PlayerResource:GetSelectedHeroEntity(event.playerid):SetTeam(DOTA_TEAM_BADGUYS)
	elseif event.text == "radiant" then
		PlayerResource:GetPlayer(event.playerid):SetTeam(DOTA_TEAM_GOODGUYS)
		PlayerResource:GetSelectedHeroEntity(event.playerid):SetTeam(DOTA_TEAM_GOODGUYS)
	end

	if event.text == "-kill" then
		PlayerResource:GetSelectedHeroEntity(event.playerid):ForceKill(false)
	end
	if StringStartsWith(event.text, "-") then
        local input = split(string.sub(event.text, 2, string.len(event.text)))
        local command = input[1]
		if command == "addrunes" then
			if input[2] then
				PlayerResource:GetSelectedHeroEntity(event.playerid):ModifyRunes(tonumber(input[2]))
			else
				PlayerResource:GetSelectedHeroEntity(event.playerid):ModifyRunes(1)
			end
		end
  	end
end
	

function Caravans:DropPresent(attacker,target)
	--if self.presents > 0 then
		--self.presents = self.presents - 1


		local item = CreateItem("item_present",nil,nil)
		local container = CreateItemOnPositionForLaunch(target:GetAbsOrigin(),item)
		if attacker:GetRangeToUnit(target) > 300 then
			pos = target:GetAbsOrigin() 
				+ 300*(attacker:GetAbsOrigin()-target:GetAbsOrigin()):Normalized() 
				+ RandomVector(RandomInt(-100,100))
		else
			pos = attacker:GetAbsOrigin() + RandomVector(RandomInt(-100,100))
		end
		item:LaunchLoot(false,250,0.5,pos)


		vision = function(container) 
			AddFOWViewer(DOTA_TEAM_BADGUYS,container:GetAbsOrigin(), 16, 1, false)
			AddFOWViewer(DOTA_TEAM_GOODGUYS,container:GetAbsOrigin(), 16, 1, false)
			return 0.5
		end

		container:SetContextThink("Vision",vision,0.5)


	--end
end 

function Caravans:PickupPresent(hero)
	hero.presents = (hero.presents or 0) + 1
	print(hero.presents)

	--[[if hero:GetTeamNumber() == DOTA_TEAM_BADGUYS then
		Caravans:IncrementDirePresents()
	end]]

	--hero:RemoveModifierByName("modifier_presents")
	hero:AddNewModifier(hero,nil,"modifier_presents",{duration = -1}):SetStackCount(hero.presents)
end



function Caravans:OnFirstHeroSpawn()
	Caravans:InitSpawnPoints()
end
function Caravans:StartSalvesSpawn()
	Timers:CreateTimer(1,function()
			for i=1,12 do
				local spawnpoint = Entities:FindByName(nil,"heal_" .. i)
				if spawnpoint.heal == nil then
	              	local item = CreateItem("item_healing_salve_use", nil, nil)
	            	CreateItemOnPositionSync(spawnpoint:GetOrigin(),item)
	                item:SetPurchaseTime(0)
					spawnpoint.heal = item
					item.spawn = spawnpoint
				end
			end
		return 30
   	end)
end
function Caravans:OnItemPickedUp(keys)
  	local unitEntity = nil
  	if keys.UnitEntitIndex then
    	unitEntity = EntIndexToHScript(keys.UnitEntitIndex)
  	elseif keys.HeroEntityIndex then
    	unitEntity = EntIndexToHScript(keys.HeroEntityIndex)
  	end
	local itemEntity = EntIndexToHScript(keys.ItemEntityIndex)
	local player = PlayerResource:GetPlayer(keys.PlayerID)
	local itemname = keys.itemname
	if itemEntity.spawn then
		itemEntity.spawn.heal = nil
	end
end

function Caravans:InitSpawnPoints()
	for i=1,4 do
		local spawnpointabs = Entities:FindByName(nil,"spawn_" .. i):GetOrigin()
		local spawnpoint = CreateUnitByName("spawnpoint",spawnpointabs,false,nil,nil,5)
		spawnpoint:AddNewModifier(spawnpoint,nil,"modifier_spawnpoint",{})
		spawnpoint.number = i
		Caravans:CreateTotemsParticles(spawnpoint,false)
	end
end

function Caravans:CreateTotemsParticles(spawnpoint,fast)
	local number = 1
	Caravans:DestroyTotemParticle(spawnpoint,true)
	Timers:CreateTimer(0.1,function()
			local part = ParticleManager:CreateParticle("particles/respawntotem.vpcf",PATTACH_ABSORIGIN,spawnpoint)
			local abs = Entities:FindByName(nil,"spawnpart_"..number.."_"..spawnpoint.number):GetOrigin()
			ParticleManager:SetParticleControl(part,0,abs+Vector(0,0,70))
			ParticleManager:SetParticleControlForward(part,0,Vector(0,0,1))
			spawnpoint[tostring("part_" .. number)] = part
			number = number + 1
			if number <= 7 then
				if not fast then
		      		return 1
		      	else
		      		return 0.01
		      	end
		    else
		    	return nil
		    end
   	end)
end

function Caravans:DestroyTotemParticle(spawnpoint,fast)
	local number = 1
	Timers:CreateTimer(function()
			if spawnpoint[tostring("part_" .. number)] then
				ParticleManager:DestroyParticle(spawnpoint[tostring("part_" .. number)],false)
				spawnpoint[tostring("part_" .. number)] = nil
			end
			number = number + 1
			if number <= 7 then
				if not fast then
		      		return 1
		      	else
		      		return 0.01
		      	end
		    else
		    	return nil
		    end
   	end)
end



--[[ Evaluate the state of the game
function Caravans:OnThink()
	if GameRules:State_Get() == DOTA_GAMERULES_STATE_GAME_IN_PROGRESS then
		--print( "Template addon script is running." )
	elseif GameRules:State_Get() >= DOTA_GAMERULES_STATE_POST_GAME then
		return nil
	end
	return 1
end]]



function Caravans:OnStateChange(keys)
	if GameRules:State_Get() == DOTA_GAMERULES_STATE_GAME_IN_PROGRESS then
		Caravans:StartSalvesSpawn()
		local caravanunits = 1
		local firstcreep = CreateUnitByName("npc_dota_caravan_unit",waypoints[1],true,nil,nil,DOTA_TEAM_GOODGUYS)
		firstcreep:AddNewModifier(firstcreep,nil,"modifier_caravan",{})
		CaravanUnitTable[caravanunits] = firstcreep
		
		firstcreep:SetContextThink("AI",CaravanAI,0.5)
		firstcreep.caravanID = caravanunits

		Timers:CreateTimer(2,function()
				caravanunits = caravanunits + 1
				
				local caravanunit = CreateUnitByName("npc_dota_caravan_unit",waypoints[1],true,nil,nil,DOTA_TEAM_GOODGUYS)
				caravanunit:AddNewModifier(caravanunit,nil,"modifier_caravan",{})
				CaravanUnitTable[caravanunits] = caravanunit
				
				caravanunit.caravanID = caravanunits

				caravanunit:SetContextThink("AI",CaravanAI,0.5)
    		
    		if caravanunits < 5 then
      			return 1.5
      		else
      			return nil
      		end
    	end
  		)
	end
end

findrange = 700
function Caravans:CaravanAI(unit)
	local CanMove = true

	local IsEnemyInRange = #FindUnitsInRadius(DOTA_TEAM_BADGUYS,
								unit:GetAbsOrigin(),
								nil,
								findrange,
								DOTA_UNIT_TARGET_TEAM_FRIENDLY,
								DOTA_UNIT_TARGET_HERO,
								DOTA_UNIT_TARGET_FLAG_MAGIC_IMMUNE_ENEMIES + DOTA_UNIT_TARGET_FLAG_INVULNERABLE,
								FIND_ANY_ORDER,
								false) ~= 0

	if IsEnemyInRange then
		CanMove = false
	end

	local previousUnit = CaravanUnitTable[unit.caravanID+1]
	if previousUnit and unit:GetRangeToUnit(previousUnit) > 200 then
		CanMove = false
	end

	local nextUnit = CaravanUnitTable[unit.caravanID-1]
	if nextUnit and unit:GetRangeToUnit(nextUnit) < 140 then
		CanMove = false
	end

	

	if unit.caravanID == 1 then
		local distanceToWayPoint = (unit:GetAbsOrigin() - waypoints[curwp]):Length2D()

		if distanceToWayPoint < 25 then
			curwp = curwp + 1
		end

		if curw == 26 then Caravans:OnRoundEnd() return end

		if CanMove then
			--print(curwp,waypoints[curwp])
			unit:MoveToPosition(waypoints[curwp])
		else
			unit:Stop()
		end
	else
		if CanMove then
			--print(CaravanUnitTable,CaravanUnitTable[unit.caravanID-1],unit.caravanID)
			unit:MoveToPosition(CaravanUnitTable[unit.caravanID-1]:GetAbsOrigin())
		else
			unit:Stop()
		end
	end


	local radiantHeroes = FindUnitsInRadius(DOTA_TEAM_GOODGUYS,
								unit:GetAbsOrigin(),
								nil,
								300,
								DOTA_UNIT_TARGET_TEAM_FRIENDLY,
								DOTA_UNIT_TARGET_HERO,
								DOTA_UNIT_TARGET_FLAG_MAGIC_IMMUNE_ENEMIES + DOTA_UNIT_TARGET_FLAG_INVULNERABLE,
								FIND_ANY_ORDER,
								false)

	for _,hero in pairs(radiantHeroes) do
		if hero.presents and hero.presents > 0 then

			local dropTime = RandomFloat(0.4,0.7)
			local container = Caravans:DropPresent(hero,unit:GetAbsOrigin() + unit:GetForwardVector()*RandomInt(-30,30), dropTime,false)
			Timers:CreateTimer(dropTime,function() 
				container:GetContainedItem():RemoveSelf() 
				container:RemoveSelf() 
				Caravans:IncrementCaravanPresents()
				--print(Caravans.presentsInCaravan)
			end)

			hero.presents = hero.presents - 1
			hero:AddNewModifier(hero,nil,"modifier_presents",{duration = -1}):SetStackCount(hero.presents)
		end
	end


	return 0.1
end
function Caravans:ClientUpdatePresents()
		CustomNetTables:SetTableValue("caravan","Presents",
		{ 
			direPresents = self.direPresents,
			presentsInCaravan = self.presentsInCaravan,
			direPresentsTotal = self.direPresentsTotal,
			radiantPresentsTotal = self.radiantPresentsTotal
		}
	)
end

function Caravans:IncrementCaravanPresents()
	self.presentsInCaravan = self.presentsInCaravan + 1
	self:ClientUpdatePresents()
end

function Caravans:DecrementCaravanPresents()
	self.presentsInCaravan = self.presentsInCaravan - 1

    if self.direPresents < 0 then
    	print("[CARAVANS] Caravan have "..self.presentsInCaravan.." presents")
    end

	self:ClientUpdatePresents()
end

function Caravans:IncrementDirePresents()
	self.direPresents = self.direPresents + 1
	self:ClientUpdatePresents()
end

function Caravans:DecrementDirePresents()
    self.direPresents = self.direPresents - 1
    
    if self.direPresents < 0 then
    	print("[CARAVANS] Dire have "..self.direPresents.." presents")
    end

	self:ClientUpdatePresents()
end


function Caravans:SetDirePresents(n)
	self.direPresents = n
	self:ClientUpdatePresents()
end

function SpawnOnRandomTotem(hero)
	local random = RandomInt(1,4)
	local spawnpointabs = Entities:FindByName(nil,"spawn_" .. random):GetOrigin()
	FindClearSpaceForUnit(hero,spawnpointabs,true)
end
function SpawnOnSpawnPoint(hero)
	local spawnpointabs = Entities:FindByName(nil,"spawn_" .. hero.selectedspawnpoint):GetOrigin()
	FindClearSpaceForUnit(hero,spawnpointabs,true)
	hero:ModifyRunes(-CARAVANS_RUNES_SPAWN_COST)
end


function Caravans:FilterExecuteOrder( filterTable )
	local units = filterTable["units"]
	local order_type = filterTable["order_type"]
	local issuer = filterTable["issuer_player_id_const"]
	local abilityIndex = filterTable["entindex_ability"]
	local targetIndex = filterTable["entindex_target"]
	local x = tonumber(filterTable["position_x"])
	local y = tonumber(filterTable["position_y"])
	local z = tonumber(filterTable["position_z"])
	local point = Vector(x,y,z)
	local queue = filterTable["queue"] == 1
	if not units["0"] then
	    return true
	end
	if order_type == DOTA_UNIT_ORDER_GLYPH then
	    return false
	end
	if order_type == DOTA_UNIT_ORDER_BUYBACK then
		return true
	end
	if GameRules:State_Get() >= DOTA_GAMERULES_STATE_POST_GAME then
		return false
	end
  	return true
end