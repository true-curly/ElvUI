local E, L, V, P, G = unpack(ElvUI)

local _G = _G
local next, type, unpack = next, type, unpack
local min, max = min, max
local wipe, tinsert = wipe, tinsert

local CreateFrame = CreateFrame
local GetCursorPosition = GetCursorPosition
local issecretvalue = issecretvalue
local UIParent = UIParent

-- Forever: in gamepad mode Blizzard's menu runs gamepad code (smart navigation, prompts, the interact
-- target) when it opens and closes. Opened from ElvUI (minimap and datatext menus) that code ran with
-- ElvUI's taint, and closing the menu raised "[ADDON_ACTION_FORBIDDEN] AddOn 'ElvUI' tried to call the
-- protected function 'SetPreferredGamepadInteractTarget()'". So in gamepad mode E:ComplicatedMenu draws
-- its menus with these ElvUI frames, which Blizzard's gamepad code doesn't know about.

local BUTTON_HEIGHT = 18
local PADDING = 6
local CHECK_WIDTH = 16
local ICON_WIDTH = 18
local ARROW_WIDTH = 14
local MIN_WIDTH = 120
local MAX_WIDTH = 360

local levels = {} -- one frame per menu level, the root is level 1
local OpenLevel, CloseFrom, CloseAll, Refresh

local function Resolve(value, list)
	if type(value) == 'function' then
		return value(list)
	end

	return value
end

local function GetTextWidth(fs)
	local width = fs:GetStringWidth()
	if not width or (issecretvalue and issecretvalue(width)) then
		return MIN_WIDTH
	end

	return width
end

-- Same rules as the Modern path in E:ComplicatedMenu: entries need a func, an arrow or a title;
-- a menuList without an arrow is flattened into the current level
local function BuildEntries(menuList, entries)
	for _, list in next, menuList do
		if list.isTitle or list.func or list.hasArrow then
			tinsert(entries, list)
		end

		if list.menuList and not list.hasArrow then
			BuildEntries(list.menuList, entries)
		end
	end

	return entries
end

local function IsOverMenu()
	for _, frame in next, levels do
		if frame:IsShown() and frame:IsMouseOver() then
			return true
		end
	end
end

local function OnGlobalMouseDown()
	if not IsOverMenu() then
		CloseAll()
	end
end

local function GetLevel(level)
	local frame = levels[level]
	if frame then return frame end

	frame = CreateFrame('Frame', 'ElvUI_GamepadMenu'..level, UIParent)
	frame:SetTemplate('Transparent')
	frame:SetFrameStrata('FULLSCREEN_DIALOG')
	frame:SetFrameLevel(100 + level * 10)
	frame:SetClampedToScreen(true)
	frame:EnableMouse(true)
	frame:Hide()

	frame.level = level
	frame.rows = {}
	frame.entries = {}
	levels[level] = frame

	if level == 1 then
		frame:SetScript('OnEvent', OnGlobalMouseDown)
		frame:SetScript('OnShow', function(menu) menu:RegisterEvent('GLOBAL_MOUSE_DOWN') end)
		frame:SetScript('OnHide', function(menu)
			menu:UnregisterEvent('GLOBAL_MOUSE_DOWN')
			CloseFrom(2)
		end)
	end

	return frame
end

local function RowOnEnter(row)
	local list = row.list
	if not list or list.isTitle then return end

	local level = row:GetParent().level
	if list.hasArrow and list.menuList and row.enabled then
		OpenLevel(level + 1, list.menuList, row)
	else
		CloseFrom(level + 1)
	end
end

local function RowOnClick(row)
	local list = row.list
	if not list or not row.enabled or list.isTitle then return end

	if not list.func then -- arrow only
		if list.hasArrow and list.menuList then
			OpenLevel(row:GetParent().level + 1, list.menuList, row)
		end

		return
	end

	local checked = row.checked
	if list.keepShownOnClick then
		list.func(row, list.arg1, list.arg2, checked)
		Refresh()
	else
		CloseAll()
		list.func(row, list.arg1, list.arg2, checked)
	end
end

local function GetRow(frame, index)
	local row = frame.rows[index]
	if row then return row end

	row = CreateFrame('Button', nil, frame)
	row:Height(BUTTON_HEIGHT)
	row:RegisterForClicks('LeftButtonUp')

	local highlight = row:CreateTexture(nil, 'HIGHLIGHT')
	highlight:SetAllPoints()
	highlight:SetColorTexture(1, 1, 1, 0.15)

	local check = CreateFrame('Frame', nil, row)
	check:Size(12)
	check:SetTemplate()
	check:Point('LEFT', row, 'LEFT', 1, 0)
	row.check = check

	local mark = check:CreateTexture(nil, 'ARTWORK')
	mark:SetTexture(E.media.normTex)
	mark:SetVertexColor(unpack(E.media.rgbvaluecolor))
	mark:SetInside()
	check.mark = mark

	local icon = row:CreateTexture(nil, 'ARTWORK')
	icon:Size(14)
	row.icon = icon

	local arrow = row:CreateTexture(nil, 'ARTWORK')
	arrow:Size(12)
	arrow:Point('RIGHT', row, 'RIGHT', 0, 0)
	arrow:SetTexture(E.Media.Textures.ArrowUp)
	arrow:SetRotation(E:GetModule('Skins').ArrowRotation.right)
	arrow:SetVertexColor(unpack(E.media.rgbvaluecolor))
	row.arrow = arrow

	local text = row:CreateFontString(nil, 'OVERLAY')
	text:FontTemplate()
	text:SetJustifyH('LEFT')
	text:SetWordWrap(false)
	row.text = text

	row:SetScript('OnEnter', RowOnEnter)
	row:SetScript('OnClick', RowOnClick)

	frame.rows[index] = row

	return row
end

local function UpdateRow(row)
	local list = row.list

	if list.isTitle then
		row.enabled = false
		row.text:SetTextColor(1, 0.82, 0)
	else
		row.enabled = not Resolve(list.disabled, list)

		if row.enabled then
			row.text:SetTextColor(1, 1, 1)
		else
			row.text:SetTextColor(0.5, 0.5, 0.5)
		end
	end

	local checkable = list.checked ~= nil and not list.notCheckable
	row.checked = checkable and Resolve(list.checked, list) and true or false
	row.check:SetShown(checkable)
	row.check.mark:SetShown(row.checked)
end

local function SetupRow(row, list, textLeft)
	row.list = list
	row.value = list.value
	row.arg1 = list.arg1
	row.arg2 = list.arg2

	local left = textLeft
	if list.icon then
		row.icon:SetTexture(list.icon)
		row.icon:SetTexCoord(unpack(list.cropIcon and E.TexCoords or {0, 1, 0, 1}))
		row.icon:ClearAllPoints()
		row.icon:Point('LEFT', row, 'LEFT', left, 0)
		row.icon:Show()

		left = left + ICON_WIDTH
	else
		row.icon:Hide()
	end

	row.text:ClearAllPoints()
	row.text:Point('LEFT', row, 'LEFT', left, 0)
	row.text:Point('RIGHT', row, 'RIGHT', -ARROW_WIDTH, 0)
	row.text:SetText(list.text or '')

	row.arrow:SetShown(list.hasArrow and list.menuList and true or false)
	row:EnableMouse(not list.isTitle)

	UpdateRow(row)

	return left + GetTextWidth(row.text)
end

local function SetRootAnchor(frame, menuFrame, anchor, x, y)
	if anchor ~= 'cursor' and menuFrame and menuFrame.relativeTo then -- set by E:SetEasyMenuAnchor
		frame:SetPoint(menuFrame.point or 'TOPLEFT', menuFrame.relativeTo, menuFrame.relativePoint or 'BOTTOMLEFT', menuFrame.xOffset or 0, menuFrame.yOffset or 0)
	else
		local scale = UIParent:GetEffectiveScale()
		local cursorX, cursorY = GetCursorPosition()
		frame:SetPoint('TOPLEFT', UIParent, 'BOTTOMLEFT', (cursorX / scale) + (x or 0), (cursorY / scale) + (y or 0))
	end
end

OpenLevel = function(level, menuList, parentRow, menuFrame, anchor, x, y)
	CloseFrom(level + 1)

	local frame = GetLevel(level)
	if frame:IsShown() and frame.menuList == menuList then return end
	frame.menuList = menuList

	local entries = BuildEntries(menuList, wipe(frame.entries))

	local textLeft = 0
	for _, list in next, entries do
		if list.checked ~= nil and not list.notCheckable then
			textLeft = CHECK_WIDTH
			break
		end
	end

	local width, offset = 0, -PADDING
	for index, list in next, entries do
		local row = GetRow(frame, index)
		row:ClearAllPoints()
		row:Point('TOPLEFT', frame, 'TOPLEFT', PADDING, offset)
		row:Point('RIGHT', frame, 'RIGHT', -PADDING, 0)
		row:Show()

		width = max(width, SetupRow(row, list, textLeft))
		offset = offset - BUTTON_HEIGHT
	end

	for index = #entries + 1, #frame.rows do
		local row = frame.rows[index]
		row:Hide()
		row.list = nil
	end

	frame:Width(min(MAX_WIDTH, max(MIN_WIDTH, width + ARROW_WIDTH + (PADDING * 2) + 4)))
	frame:Height(PADDING - offset)

	frame:ClearAllPoints()
	if parentRow then
		frame:Point('TOPLEFT', parentRow, 'TOPRIGHT', PADDING, PADDING)
	else
		SetRootAnchor(frame, menuFrame, anchor, x, y)
	end

	frame:Show()
end

CloseFrom = function(level)
	for index = #levels, level, -1 do
		local frame = levels[index]
		if frame:IsShown() then
			frame:Hide()
		end

		frame.menuList = nil
	end
end

CloseAll = function()
	CloseFrom(1)
end

Refresh = function()
	for _, frame in next, levels do
		if frame:IsShown() then
			for _, row in next, frame.rows do
				if row.list and row:IsShown() then
					UpdateRow(row)
				end
			end
		end
	end
end

function E:GamepadMenu_Show(menuList, menuFrame, anchor, x, y)
	CloseAll()
	OpenLevel(1, menuList, nil, menuFrame, anchor, x, y)
end

function E:GamepadMenu_Close()
	CloseAll()
end

function E:GamepadMenu_IsShown()
	local root = levels[1]
	return root and root:IsShown()
end
