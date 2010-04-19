-- Einstellungen
local Prefix = "SindraGOZER: " -- Präfix für z.B. die Whispers
local Broadcast = "RAID_WARNING" -- Channel in den gespamt wird

-- Spell ID des Frost Beacons
local FrostBeaconID = 70126

-- Spell ID von Unchained Magic
local UnchainedMagicID = 69762

-- Spellid der Frostbomb im 25er Heroic
local FrostBombID = 71055

-- Spell IDs des Mystic Buffet
local MysticBuffetID = {
	[72528] = true,
	[72530] = true,
	[70127] = true,
	[72529] = true
}

-- alle unsere Combatlog Daten
local timestamp, type, srcGUID, srcName, srcFlgs, dstGUID, dstName, dstFlgs, spellID, spellName, spellSchool, auraType, amount

-- Frame bauen
local SindraGOZER = CreateFrame("FRAME", "SindraGOZER")

-- Eventhandling (als Lambda-Funktion)
SindraGOZER:SetScript("OnEvent",
	function(self, event, ...)
		if event == "COMBAT_LOG_EVENT_UNFILTERED" then
			-- http://www.wowwiki.com/API_COMBAT_LOG_EVENT#Base_Parameters
			timestamp, type, srcGUID, srcName, srcFlgs, dstGUID, dstName, dstFlgs = select(1, ...)
			--  AUREN    
			if type:sub(1,18) == "SPELL_AURA_APPLIED" then
				-- http://www.wowwiki.com/API_COMBAT_LOG_EVENT#Prefixes
				-- http://www.wowwiki.com/API_COMBAT_LOG_EVENT#Suffixes
				spellID, spellName, spellSchool, auraType, amount = select(9, ...)				
				-- nur Spieler tracken
				if not UnitInRaid(dstName) then return end				
				-- Mystic Buffet
				if MysticBuffetID[spellID] and amount == 6 then
					self:MysicBuffetAnnounce()
				-- Unchained Magic
				elseif spellID == UnchainedMagicID and difficulty == 4 then				
					self:UnchainedMagic()				
				-- Frost Beacon
				elseif spellID == FrostBeaconID then
					self:Beacons()
				end
			elseif type:sub(1,18) == "SPELL_AURA_REMOVED" then
				spellID, spellName = select(9, ...)
				-- Reset der Icons (Frost Beacon & Unchained Magic)
				if spellID == FrostBeaconID or spellID == UnchainedMagicID then
					self:RemoveRaidIcon()
				end
			elseif srcName == "Frost Bomb" then
				spellID, spellName, spellSchool, auraType, amount = select(9, ...)
				-- Frost Bomb
				if spellID == FrostBombID then
					self:FrostBombAnnounce()
				end
			end
			
		elseif event:sub(1,12) == "ZONE_CHANGED" then			
			self:CheckZone()
		elseif event == "ADDON_LOADED" then
			self:Initialize()
		end
	end
)
SindraGOZER:RegisterEvent("ADDON_LOADED")

function SindraGOZER:Initialize()
	self:UnregisterEvent("ADDON_LOADED")
	self:message("loaded")
	self:RegisterEvent("ZONE_CHANGED")
	self:RegisterEvent("ZONE_CHANGED_INDOORS")
	self:RegisterEvent("ZONE_CHANGED_NEW_AREA")	
	self:CheckZone()
end

local subzone    = GetSubZoneText()
local difficulty = GetInstanceDifficulty()
function SindraGOZER:CheckZone()
	-- Wenn wir uns in der ICC25 befinden (EN und DE)
	-- http://www.wowwiki.com/API_GetDungeonDifficulty
	-- http://www.wowwiki.com/API_GetSubZoneText
	subzone    = GetSubZoneText()
	-- Workaround für die ICC Heroic (http://forums.wowace.com/showthread.php?t=17936)
	local _, _, diff, _, _, hero, flag = GetInstanceInfo(); 
	difficulty = (flag and (2-(diff%2)+2*hero)) or diff;
	-- Testoutput
	self:message("Difficulty: "..difficulty)
	-- hässlich, sollte mir mal was anderes einfallen lassen
	if subzone == "The Frost Queen's Lair" or subzone == "Der Hort der Frostkönigin"  then
		self:message("Looking for |TInterface\\Icons\\ability_hunter_markedfordeath:16|tFrost Beacons and |TInterface\\Icons\\spell_arcane_arcane03:16|tMystic Buffets!")
		self:RegisterEvent("COMBAT_LOG_EVENT_UNFILTERED")
	else
		self:UnregisterEvent("COMBAT_LOG_EVENT_UNFILTERED")
	end
end

local Raidicons = {1,2,3,4,6,5} -- http://www.wowwiki.com/API_SetRaidTarget
local beaconTargets = {} -- Tabelle in der die Spieler reingeschrieben werden
local lastBeaconTimestamp = time() -- Zeitstempel zum resetten der Liste
local beacon_delta = 5 -- Sekunden die zwischen den Beacon Casts maximal liegen dürfen
local numBeacons = {2,5,2,6} --  Index 1-4, entspricht der DungeoDifficulty
local Whispers = {} -- wird der Reihe nach an die Frost Beacon Opfer gesendet
Whispers[1] = { --  10 Normal
	"( ) (x)",
	"(x) ( )"
}
Whispers[2] = { --  25 Normalmode
	"( ) ( ) (x)",
	"( ) (x) ( )",
	"(x) ( ) ( )",
	"  ( ) (x)  ",
	"  (x) ( )  "
}
Whispers[3] = { --  10 Heroic
	"( ) (x)",
	"(x) ( )"
}
Whispers[4] = { --  25 Normalmode
	"( ) ( ) (x)",
	"( ) ( ) (x)",
	"( ) (x) ( )",
	"( ) (x) ( )",
	"(x) ( ) ( )",
	"(x) ( ) ( )"
}
function SindraGOZER:Beacons()
	-- Reset der Beacons
	if #beaconTargets > numBeacons[difficulty] or difftime(time(),lastBeaconTimestamp) > beacon_delta then
		beaconTargets = wipe(beaconTargets)
	end	
	-- Zeit setzen
	lastBeaconTimestamp = time()
	-- Die Tabelle der Reihenfolge mit Namen der Spieler befüllen
	beaconTargets[#beaconTargets + 1] = dstName
	-- sobald wir alle Beacons gesammelt haben
	if #beaconTargets == numBeacons[difficulty] then
		-- evtl. sollte sowas vorher abgeprüft werden
		if IsRaidOfficer() or IsRaidLeader() then
			-- HAESSLICH ... muss schöner gehen!
			if difficulty == 1 then
				self:channel(format("    ({rt%u}%s)   ({rt%u}%s)",Raidicons[2],beaconTargets[2],Raidicons[1],beaconTargets[1]))
			elseif difficulty == 2 then				
				self:channel(format("           ({rt%u}%s)   ({rt%u}%s)",Raidicons[5],beaconTargets[5],Raidicons[4],beaconTargets[4]))				
				self:channel(format("   ({rt%u}%s)   ({rt%u}%s)   ({rt%u}%s)",Raidicons[3],beaconTargets[3],Raidicons[2],beaconTargets[2],Raidicons[1],beaconTargets[1]))
			elseif difficulty == 3 then
				self:channel(format("    ({rt%u}%s)   ({rt%u}%s)",Raidicons[2],beaconTargets[2],Raidicons[1],beaconTargets[1]))
			elseif difficulty == 4 then
				self:channel(format("   ({rt%u}%s {rt%u}%s)   ({rt%u}%s {rt%u}%s)   ({rt%u}%s {rt%u}%s)",Raidicons[6],beaconTargets[6],Raidicons[5],beaconTargets[5],Raidicons[4],beaconTargets[4],Raidicons[3],beaconTargets[3],Raidicons[2],beaconTargets[2],Raidicons[1],beaconTargets[1]))
			end
			for n = 1, numBeacons[difficulty], 1 do
				-- Raidtarget Icons setzen
				SetRaidTarget(beaconTargets[n],Raidicons[n])
				-- Whispers
				self:whisper(Whispers[difficulty][n], beaconTargets[n])
			end
		else
			self:message("You need to be leader or assistant to do this.")
		end
	end
end

local unchainedTargets = {} -- Tabelle in der die Spieler reingeschrieben werden
local lastUnchainedTimestamp = time()
local unchained_delta = 5
local numUnchained = {2,6,2,6} --  Index 1-4, entspricht der DungeoDifficulty
function SindraGOZER:UnchainedMagic()
	-- Reset der Beacons
	if #unchainedTargets > numUnchained[difficulty] or difftime(time(),lastUnchainedTimestamp) > unchained_delta then
		unchainedTargets = wipe(unchainedTargets)
	end	
	-- Zeit setzen
	lastUnchainedTimestamp = time()
	-- Die Tabelle der Reihenfolge mit Namen der Spieler befüllen
	unchainedTargets[#unchainedTargets + 1] = dstName
	-- sobald wir alle Beacons gesammelt haben
	if #unchainedTargets == numUnchained[difficulty] then
		-- evtl. sollte sowas vorher abgeprüft werden
		if IsRaidOfficer() or IsRaidLeader() then
			for n = 1, numUnchained[difficulty], 1 do
				-- Raidtarget Icons setzen
				SetRaidTarget(unchainedTargets[n],Raidicons[n])
			end
		else
			self:message("You need to be leader or assistant to do this.")
		end
	end
end

function SindraGOZER:RemoveRaidIcon()
	SetRaidTarget(dstName,0)
end

function SindraGOZER:MysicBuffetAnnounce()
	local msg = format("%s took too many stacks!", dstName)
	if IsRaidOfficer() or IsRaidLeader() then
		self:channel(Prefix..msg, "RAID")
	else
		self:message(msg)
	end	
end

function SindraGOZER:FrostBombAnnounce()
	local msg = format("%s died in a Frost Bomb!", dstName)
	if IsRaidOfficer() or IsRaidLeader() then
		self:channel(Prefix..msg, "RAID")
	else
		self:message(msg)
	end	
end
--  HELPER  ZEUGS
function SindraGOZER:whisper(msg, name)
   if not (msg and name) then return end   
   SendChatMessage(Prefix..msg, "WHISPER", nil, name)
end

function SindraGOZER:channel(msg, ...)
	chan = ...
	if msg then
		if not chan then 
			SendChatMessage(msg, Broadcast, nil)
		else
			SendChatMessage(msg, chan, nil)
		end
	end	
end

local print,format = print,string.format
function SindraGOZER:message(msg)
	if msg then
		print(format("|cff0099ff"..Prefix.."|r%s",msg))
	end
end

--  Chat-Filter
function filterOutgoing(self, event, ...)
	local msg = ...
	if not msg and self then
		return filterOutgoing(nil, nil, self, event)
	end
	-- wir gucken ob der anfang der msg gleich unserem Prefix ist
	return msg:sub(1, Prefix:len()) == Prefix, ...
end
-- Filter muss noch registriert werden
ChatFrame_AddMessageEventFilter("CHAT_MSG_WHISPER_INFORM", filterOutgoing)