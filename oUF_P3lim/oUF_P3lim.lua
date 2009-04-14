local format = string.format
local floor = math.floor
local localized, class = UnitClass('player')
local texture = [=[Interface\AddOns\oUF_P3lim\minimalist]=]
local backdrop = {
	bgFile = [=[Interface\ChatFrame\ChatFrameBackground]=],
	insets = {top = -1, left = -1, bottom = -1, right = -1},
}

local runeloadcolors = {
	[1] = {0.77, 0.12, 0.23},
	[2] = {0.77, 0.12, 0.23},
	[3] = {0.4, 0.8, 0.1},
	[4] = {0.4, 0.8, 0.1},
	[5] = {0, 0.4, 0.7},
	[6] = {0, 0.4, 0.7},
}

local colors = setmetatable({
	power = setmetatable({
		['MANA'] = {0, 144/255, 1}
	}, {__index = oUF.colors.power}),
	reaction = setmetatable({
		[2] = {1, 0, 0},
		[4] = {1, 1, 0},
		[5] = {0, 1, 0}
	}, {__index = oUF.colors.reaction}),
	red = {1, 0, 0},
	white = {1, 1, 1},
}, {__index = oUF.colors})

local function menu(self)
	local unit = string.gsub(self.unit, '(.)', string.upper, 1)
	if(_G[unit..'FrameDropDown']) then
		ToggleDropDownMenu(1, nil, _G[unit..'FrameDropDown'], 'cursor')
	end
end

local function truncate(value)
	if(value >= 1e6) then
		return format('%dm', value / 1e6)
	elseif(value >= 1e4) then
		return format('%dk', value / 1e3)
	else
		return value
	end
end

oUF.TagEvents['[customstatus]'] = 'UNIT_HEALTH'
oUF.Tags['[customstatus]'] = function(unit)
	return not UnitIsConnected(unit) and 'Offline' or UnitIsGhost(unit) and 'Ghost' or UnitIsDead(unit) and 'Dead'
end

oUF.TagEvents['[customhp]'] = 'UNIT_HEALTH UNIT_MAXHEALTH'
oUF.Tags['[customhp]'] = function(unit)
	local status = oUF.Tags['[customstatus]'](unit)
	local min, max = UnitHealth(unit), UnitHealthMax(unit)

	return status and status or 
		(unit == 'target' and UnitCanAttack('player', unit)) and format('%s (%d|cff0090ff%%|r)', truncate(min), floor(min/max*100)) or
		(unit == 'player' and min~=max) and format('|cffff8080%d|r %d|cff0090ff%%|r', min-max, floor(min/max*100)) or
		(unit == 'pet' and min~=max) and format('%s |cff0090ff/|r %s', truncate(min), truncate(max)) or
		(min~=max) and format('%s |cff0090ff/|r %s', min, max) or max
end

oUF.TagEvents['[custompp]'] = oUF.TagEvents['[curpp]']
oUF.Tags['[custompp]'] = function(unit)
	local num, str = UnitPowerType(unit)
	local c = colors.power[str]
	return c and format('|cff%02x%02x%02x%s|r', c[1] * 255, c[2] * 255, c[3] * 255, oUF.Tags['[curpp]'](unit))
end

oUF.TagEvents['[customname]'] = 'UNIT_NAME_UPDATE UNIT_REACTION UNIT_FACTION'
oUF.Tags['[customname]'] = function(unit)
	local c = (UnitIsTapped(unit) and not UnitIsTappedByPlayer(unit)) and colors.tapped or
		(not UnitIsConnected(unit)) and colors.disconnected or
		(not UnitIsPlayer(unit)) and colors.reaction[UnitReaction(unit, 'player')] or
		(UnitFactionGroup(unit) and UnitIsPVP(unit)) and colors.red or colors.white

	return format('|cff%02x%02x%02x%s|r', c[1] * 255, c[2] * 255, c[3] * 255, UnitName(unit))
end

oUF.TagEvents['[druidpower]'] = 'UNIT_MANA UPDATE_SHAPESHIFT_FORM'
oUF.Tags['[druidpower]'] = function(unit)
	local min, max = UnitPower(unit, 0), UnitPowerMax(unit, 0)
	return UnitPowerType(unit) ~= 0 and format('|cff0090ff%d - %d%%|r', min, math.floor(min / max * 100))
end

local function updateMasterLooter(self)
	self.MasterLooter:ClearAllPoints()
	if((UnitInParty(self.unit) or UnitInRaid(self.unit)) and UnitIsPartyLeader(self.unit)) then
		self.MasterLooter:SetPoint('LEFT', self.Leader, 'RIGHT')
	else
		self.MasterLooter:SetPoint('TOPLEFT', self, 0, 8)
	end
end

local function updateDruidPower(self, event, unit)
	if(unit and unit ~= self.unit) then return end
	local bar = self.DruidPower

	local mana = UnitPowerType('player') == 0
	local min, max = UnitPower('player', mana and 3 or 0), UnitPowerMax('player', mana and 3 or 0)

	bar:SetStatusBarColor(unpack(colors.power[mana and 'ENERGY' or 'MANA']))
	bar:SetMinMaxValues(0, max)
	bar:SetValue(min)
	bar:SetAlpha(min ~= max and 1 or 0)
end

local function updateReputationColor(self, event, unit, bar)
	local name, id = GetWatchedFactionInfo()
	bar:SetStatusBarColor(FACTION_BAR_COLORS[id].r, FACTION_BAR_COLORS[id].g, FACTION_BAR_COLORS[id].b)
end

local function castbarTime(self, duration)
	if(self.channeling) then
		self.Time:SetFormattedText('%.1f ', duration)
	elseif(self.casting) then
		self.Time:SetFormattedText('%.1f ', self.max - duration)
	end
end

local function createAura(icons, button)
	icons.showDebuffType = true
	button.cd:SetReverse()
	button.overlay:SetTexture([=[Interface\AddOns\oUF_P3lim\border]=])
	button.overlay:SetTexCoord(0, 1, 0, 1)
	button.overlay.Hide = function(self) self:SetVertexColor(0.25, 0.25, 0.25) end
end

local function updateAura(icons, unit, icon, index)
	if(icon.debuff and UnitIsEnemy('player', unit)) then
		local _, _, _, _, _, duration, _, caster = UnitAura(unit, index, icon.filter)
		if(caster ~= 'player' and caster ~= 'vehicle') then
			icon.icon:SetDesaturated(true)
			icon.overlay:SetVertexColor(0.25, 0.25, 0.25)
		else
			icon.icon:SetDesaturated(false)
		end
	end
end

local function styleFunction(self, unit)
	self.colors = colors

	self.menu = menu
	self:RegisterForClicks('AnyUp')
	self:SetAttribute('type2', 'menu')

	self:SetScript('OnEnter', UnitFrame_OnEnter)
	self:SetScript('OnLeave', UnitFrame_OnLeave)

	self:SetBackdrop(backdrop)
	self:SetBackdropColor(0, 0, 0)

	self.Health = CreateFrame('StatusBar', self:GetName()..'_health', self)
	self.Health:SetPoint('TOPRIGHT', self)
	self.Health:SetPoint('TOPLEFT', self)
	self.Health:SetStatusBarTexture(texture)
	self.Health:SetStatusBarColor(0.25, 0.25, 0.35)
	self.Health:SetHeight((unit == 'focus' or unit == 'targettarget') and 20 or 22)
	self.Health.frequentUpdates = true

	self.Health.bg = self.Health:CreateTexture(nil, 'BORDER')
	self.Health.bg:SetAllPoints(self.Health)
	self.Health.bg:SetTexture(0.3, 0.3, 0.3)

	local hpvalue = self.Health:CreateFontString(nil, 'OVERLAY', 'GameFontHighlightSmallRight')
	hpvalue:SetPoint('RIGHT', self.Health, -2, -1)
	hpvalue.frequentUpdates = 0.1
	self:Tag(hpvalue, '[customhp]')

	self.RaidIcon = self.Health:CreateTexture(nil, 'OVERLAY')
	self.RaidIcon:SetPoint('TOP', self, 0, 8)
	self.RaidIcon:SetHeight(16)
	self.RaidIcon:SetWidth(16)

	if(unit ~= 'targettarget' and unit ~= 'focus') then
		self.Power = CreateFrame('StatusBar', self:GetName()..'_power', self)
		self.Power:SetPoint('TOPRIGHT', self.Health, 'BOTTOMRIGHT', 0, -1)
		self.Power:SetPoint('TOPLEFT', self.Health, 'BOTTOMLEFT', 0, -1)
		self.Power:SetStatusBarTexture(texture)
		self.Power:SetHeight(4)
		self.Power.frequentUpdates = true

		self.Power.bg = self.Power:CreateTexture(nil, 'BORDER')
		self.Power.bg:SetAllPoints(self.Power)
		self.Power.bg:SetTexture([=[Interface\ChatFrame\ChatFrameBackground]=])
		self.Power.bg.multiplier = 0.3

		self.Power.colorTapping = true
		self.Power.colorDisconnected = true
		self.Power.colorClass = true
		self.Power.colorPower = unit == 'pet' and true
		self.Power.colorHappiness = unit == 'pet' and true
		self.Power.colorReaction = unit ~= 'pet' and true

		self.Castbar = CreateFrame('StatusBar', self:GetName()..'_castbar', self)
		self.Castbar:SetPoint('TOPRIGHT', self, 'BOTTOMRIGHT', 0, -100)
		self.Castbar:SetPoint('TOPLEFT', self, 'BOTTOMLEFT', 0, -100)
		self.Castbar:SetStatusBarTexture(texture)
		self.Castbar:SetStatusBarColor(0.25, 0.25, 0.35)
		self.Castbar:SetBackdrop(backdrop)
		self.Castbar:SetBackdropColor(0, 0, 0)
		self.Castbar:SetHeight(22)

		self.Castbar.Text = self.Castbar:CreateFontString(nil, 'OVERLAY', 'GameFontHighlightSmallLeft')
		self.Castbar.Text:SetPoint('LEFT', self.Castbar, 2, -1)

		self.Castbar.Time = self.Castbar:CreateFontString(nil, 'OVERLAY', 'GameFontHighlightSmallRight')
		self.Castbar.Time:SetPoint('RIGHT', self.Castbar, -2, -1)
		self.Castbar.CustomTimeText = castbarTime

		self.Castbar.bg = self.Castbar:CreateTexture(nil, 'BORDER')
		self.Castbar.bg:SetAllPoints(self.Castbar)
		self.Castbar.bg:SetTexture(0.3, 0.3, 0.3)

		self.Leader = self.Health:CreateTexture(nil, 'OVERLAY')
		self.Leader:SetPoint('TOPLEFT', self, 0, 8)
		self.Leader:SetHeight(16)
		self.Leader:SetWidth(16)

		self.MasterLooter = self.Health:CreateTexture(nil, 'OVERLAY')
		self.MasterLooter:SetPoint('LEFT', self.Leader, 'RIGHT')
		self.MasterLooter:SetHeight(16)
		self.MasterLooter:SetWidth(16)

		table.insert(self.__elements, updateMasterLooter)
		self:RegisterEvent('PARTY_LOOT_METHOD_CHANGED', updateMasterLooter)
		self:RegisterEvent('PARTY_MEMBERS_CHANGED', updateMasterLooter)
		self:RegisterEvent('PARTY_LEADER_CHANGED', updateMasterLooter)
	else
		local f = unit == 'focus'
		self.Debuffs = CreateFrame('Frame', nil, self)
		self.Debuffs:SetPoint(f and 'TOPLEFT' or 'TOPRIGHT', self, f and 'TOPRIGHT' or 'TOPLEFT', f and 2 or -2, 1)
		self.Debuffs:SetHeight(23)
		self.Debuffs:SetWidth(180)
		self.Debuffs.num = 2
		self.Debuffs.size = 23
		self.Debuffs.spacing = 2
		self.Debuffs.onlyShowPlayer = f and true
		self.Debuffs.initialAnchor = f and 'TOPLEFT' or 'TOPRIGHT'
		self.Debuffs['growth-x'] = f and 'RIGHT' or 'LEFT'
--		self.Debuffs.PostCreateIcon = createAura -- waiting for consistency branch to be merged
		self.PostCreateAuraIcon = createAura

		self:SetAttribute('initial-height', 21)
		self:SetAttribute('initial-width', 181)
	end

	if(unit == 'player' or unit == 'pet') then
		local power = self.Health:CreateFontString(nil, 'OVERLAY', 'GameFontHighlightSmallLeft')
		power:SetPoint('LEFT', self.Health, 2, -1)
		power.frequentUpdates = 0.1
		self:Tag(power, unit == 'pet' and '[custompp] [(- )cpoints( CP)]' or '[custompp]')

		self.BarFade = true
	else
		local info = self.Health:CreateFontString(nil, 'OVERLAY', 'GameFontHighlightSmallLeft')
		info:SetPoint('LEFT', self.Health, 2, -1)
		info:SetPoint('RIGHT', hpvalue, 'LEFT')
		self:Tag(info, unit == 'target' and '[customname] |cff0090ff[smartlevel] [rare]|r' or '[customname]')
	end

	if(unit == 'pet') then
		self.Auras = CreateFrame('Frame', nil, self)
		self.Auras:SetPoint('TOPRIGHT', self, 'TOPLEFT', -2, 1)
		self.Auras:SetHeight(24 * 2)
		self.Auras:SetWidth(270)
		self.Auras.size = 24
		self.Auras.spacing = 2
		self.Auras.initialAnchor = 'TOPRIGHT'
		self.Auras['growth-x'] = 'LEFT'
--		self.Auras.PostCreateIcon = createAura -- waiting for consistency branch to be merged
		self.PostCreateAuraIcon = createAura

		self:SetAttribute('initial-height', 27)
		self:SetAttribute('initial-width', 130)
	end

	if(unit == 'target' or unit == 'player') then
		self:SetAttribute('initial-height', 27)
		self:SetAttribute('initial-width', 230)
	end

	if(unit == 'target') then
		self.CPoints = self:CreateFontString(nil, 'OVERLAY', 'SubZoneTextFont')
		self.CPoints:SetPoint('RIGHT', self, 'LEFT', -9, 0)
		self.CPoints:SetTextColor(1, 1, 1)
		self.CPoints:SetJustifyH('RIGHT')
		self.CPoints.unit = 'player'

		self.Buffs = CreateFrame('Frame', nil, self)
		self.Buffs:SetPoint('TOPLEFT', self, 'TOPRIGHT', 2, 1)
		self.Buffs:SetHeight(24 * 2)
		self.Buffs:SetWidth(270)
		self.Buffs.num = 20
		self.Buffs.size = 24
		self.Buffs.spacing = 2
		self.Buffs.initialAnchor = 'TOPLEFT'
		self.Buffs['growth-y'] = 'DOWN'
		self.Buffs.PostCreateIcon = createAura

		self.Debuffs = CreateFrame('Frame', nil, self)
		self.Debuffs:SetPoint('TOPLEFT', self, 'BOTTOMLEFT', -1, -2)
		self.Debuffs:SetHeight(22 * 0.97)
		self.Debuffs:SetWidth(230)
		self.Debuffs.size = 22 * 0.97
		self.Debuffs.spacing = 2
		self.Debuffs.initialAnchor = 'TOPLEFT'
		self.Debuffs['growth-y'] = 'DOWN'
--		self.Debuffs.PostCreateIcon = createAura -- waiting for consistency branch to be merged
--		self.Debuffs.PostUpdateIcon = updateAura -- waiting for consistency branch to be merged
		self.PostCreateAuraIcon = createAura
		self.PostUpdateAuraIcon = updateAura
	end

	if(unit == 'player' and class == 'DRUID') then
		self.DruidPower = CreateFrame('StatusBar', self:GetName()..'_druidpower', self)
		self.DruidPower:SetPoint('TOP', self.Health, 'BOTTOM')
		self.DruidPower:SetStatusBarTexture(texture)
		self.DruidPower:SetHeight(1)
		self.DruidPower:SetWidth(230)
		self.DruidPower:SetAlpha(0)

		local value = self.DruidPower:CreateFontString(nil, 'OVERLAY', 'GameFontNormalSmall')
		value:SetPoint('CENTER', self.DruidPower)
		self:Tag(value, '[druidpower]')

		table.insert(self.__elements, updateDruidPower)
		self:RegisterEvent('UNIT_MANA', updateDruidPower)
		self:RegisterEvent('UNIT_ENERGY', updateDruidPower)
		self:RegisterEvent('UPDATE_SHAPESHIFT_FORM', updateDruidPower)
	end

	if(IsAddOnLoaded'oUF_Reputation' and unit == 'player' and UnitLevel('player') == MAX_PLAYER_LEVEL) then
		self.Reputation = CreateFrame('StatusBar', self:GetName()..'_reputation', self)
		self.Reputation:SetPoint('TOP', self, 'BOTTOM', 0, -10)
		self.Reputation:SetStatusBarTexture(texture)
		self.Reputation:SetHeight(11)
		self.Reputation:SetWidth(230)
		self.Reputation:SetBackdrop(backdrop)
		self.Reputation:SetBackdropColor(0, 0, 0)
		self.Reputation.Tooltip = true
		self.Reputation.PostUpdate = updateReputationColor

		self.Reputation.Text = self.Reputation:CreateFontString(nil, 'OVERLAY', 'GameFontHighlightSmall')
		self.Reputation.Text:SetPoint('CENTER', self.Reputation)

		self.Reputation.bg = self.Reputation:CreateTexture(nil, 'BORDER')
		self.Reputation.bg:SetAllPoints(self.Reputation)
		self.Reputation.bg:SetTexture(0.3, 0.3, 0.3)
	end

	if(IsAddOnLoaded('oUF_RuneBar') and unit == 'player' and class == 'DEATHKNIGHT') then
		self.RuneBar = {}
		for i = 1, 6 do
			self.RuneBar[i] = CreateFrame('StatusBar', self:GetName()..'_runebar'..i, self)
			if(i == 1) then
				self.RuneBar[i]:SetPoint('TOPLEFT', self, 'BOTTOMLEFT', 0, -1)
			else
				self.RuneBar[i]:SetPoint('TOPLEFT', self.RuneBar[i-1], 'TOPRIGHT', 1, 0)
			end
			self.RuneBar[i]:SetStatusBarTexture(texture)
			self.RuneBar[i]:SetStatusBarColor(unpack(runeloadcolors[i]))
			self.RuneBar[i]:SetHeight(4)
			self.RuneBar[i]:SetWidth(230/6 - 0.85)
			self.RuneBar[i]:SetBackdrop(backdrop)
			self.RuneBar[i]:SetBackdropColor(0, 0, 0)
			self.RuneBar[i]:SetMinMaxValues(0, 1)

			self.RuneBar[i].bg = self.RuneBar[i]:CreateTexture(nil, 'BORDER')
			self.RuneBar[i].bg:SetAllPoints(self.RuneBar[i])
			self.RuneBar[i].bg:SetTexture(0.3, 0.3, 0.3)			
		end
	end

	if(IsAddOnLoaded('oUF_Experience') and (unit == 'pet' or unit == 'player')) then
		self.Experience = CreateFrame('StatusBar', self:GetName()..'_experience', self)
		self.Experience:SetPoint('TOP', self, 'BOTTOM', 0, -10)
		self.Experience:SetStatusBarTexture(texture)
		self.Experience:SetStatusBarColor(unpack(colors.health))
		self.Experience:SetHeight(11)
		self.Experience:SetWidth((unit == 'pet') and 130 or 230)
		self.Experience:SetBackdrop(backdrop)
		self.Experience:SetBackdropColor(0, 0, 0)
		self.Experience.Tooltip = true

		self.Experience.Text = self.Experience:CreateFontString(nil, 'OVERLAY', 'GameFontHighlightSmall')
		self.Experience.Text:SetPoint('CENTER', self.Experience)

		self.Experience.bg = self.Experience:CreateTexture(nil, 'BORDER')
		self.Experience.bg:SetAllPoints(self.Experience)
		self.Experience.bg:SetTexture(0.3, 0.3, 0.3)
	end

	self.disallowVehicleSwap = true

	self.DebuffHighlightBackdrop = true
	self.DebuffHighlightFilter = true
end

oUF:RegisterStyle('P3lim', styleFunction)
oUF:SetActiveStyle('P3lim')

oUF:Spawn('player', 'oUF_P3lim_player'):SetPoint('CENTER', UIParent, -220, -250)
oUF:Spawn('target', 'oUF_P3lim_target'):SetPoint('CENTER', UIParent, 220, -250)
oUF:Spawn('targettarget', 'oUF_P3lim_targettarget'):SetPoint('BOTTOMRIGHT', oUF_P3lim_target, 'TOPRIGHT', 0, 5)
oUF:Spawn('focus', 'oUF_P3lim_focus'):SetPoint('BOTTOMLEFT', oUF_P3lim_player, 'TOPLEFT', 0, 5)
oUF:Spawn('pet', 'oUF_P3lim_pet'):SetPoint('RIGHT', oUF_P3lim_player, 'LEFT', -25, 0)