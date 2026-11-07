--[[
	UiLibrary - a dark, two-column UI library for Roblox, drawn with the Drawing API.

	Works in executors that only have Drawing (Matcha and similar): no ScreenGui,
	no Instance.new, no TweenService. Everything is redrawn every frame and input
	is read with ismouse1pressed / iskeypressed.

	Load it straight from GitHub:

	  local Library = loadstring(game:HttpGet(
	      "https://raw.githubusercontent.com/opsecgodscripts/UiLibrary/refs/heads/main/UiLibrary/Library.lua"
	  ))()

	See test.lua for every element.

	API
	  Library:CreateWindow({ Title, Subtitle, ToggleKey, Size, Theme })  -> Window
	    ToggleKey: "RightShift", "Insert", "F1", "K" ... or a virtual-key number (0xA1)
	               or an Enum.KeyCode if the executor has Enum.
	    Size:      width in pixels (number), Vector2 or UDim2. Height fits the content.
	    Window:CreateTab({ Name, Icon })            -> Tab
	    Window:SetStatus(text, connected)           -- footer dot + text
	    Window:SetTitle(title, subtitle)
	    Window:Notify(title, text, duration)
	    Window:SelectTab(tab)
	    Window:Toggle([visible])
	    Window:Destroy()
	    Window.Flags[flag]                          -- current value of every flagged element

	  Tab:CreateSection({ Name, Side = "Left" | "Right", Icon }) -> Section
	  Tab:Select()

	  Section:AddToggle({ Name, Default, Flag, Callback })              -> :Set(bool) :Get()
	  Section:AddButton({ Name, Callback })                             -> :SetText(text)
	  Section:AddLabel(text)                                            -> :Set(text)
	  Section:AddSlider({ Name, Min, Max, Default, Increment, Suffix, Flag, Callback })
	                                                                    -> :Set(number) :Get()
	  Section:AddDropdown({ Name, Options, Default, Multi, Flag, Callback })
	                                                                    -> :Set(value) :Get() :Refresh(options)

	Callbacks only fire when the user changes a value or you call :Set(), not when
	the element is created.

	Icons are short text. Stick to plain ASCII (">", "+", "*", "#") because the
	Drawing font may not have symbols or emoji. Image icons are not supported.
]]

local Library = {}
Library.Version = "2.0.0"
Library.CharWidth = 0.55 -- width of one character as a fraction of the text size (Monospace font)

--// runtime compatibility ----------------------------------------------------
if not Color3.fromRGB then
	Color3.fromRGB = function(r, g, b)
		return Color3.new(r / 255, g / 255, b / 255)
	end
end

local Players = game:GetService("Players")
local UserInputService
pcall(function()
	UserInputService = game:GetService("UserInputService")
end)

local FONT = 3
pcall(function()
	if Drawing.Fonts then
		FONT = Drawing.Fonts.Monospace or Drawing.Fonts.UI or FONT
	end
end)

local spawnTask = (task and task.spawn) or function(fn, ...)
	return coroutine.wrap(fn)(...)
end
local waitTask = (task and task.wait) or wait

local unpack = table.unpack or unpack

local function now()
	return os.clock()
end

local function clamp(v, lo, hi)
	if v < lo then
		return lo
	elseif v > hi then
		return hi
	end
	return v
end

local function lerp(a, b, t)
	return a + (b - a) * t
end

local function log(...)
	local parts = { "[UiLibrary]" }
	for i = 1, select("#", ...) do
		parts[#parts + 1] = tostring((select(i, ...)))
	end
	print(table.concat(parts, " "))
end

local function runCallback(callback, ...)
	if type(callback) ~= "function" then
		return
	end
	local args = { ... }
	local n = select("#", ...)
	spawnTask(function()
		local ok, err = pcall(callback, unpack(args, 1, n))
		if not ok then
			log("callback error:", err)
		end
	end)
end

--// theme --------------------------------------------------------------------
local DefaultTheme = {
	Background = Color3.fromRGB(17, 17, 21),
	Section = Color3.fromRGB(23, 23, 28),
	Element = Color3.fromRGB(31, 31, 37),
	ElementHover = Color3.fromRGB(39, 39, 46),
	Border = Color3.fromRGB(37, 37, 44),
	Accent = Color3.fromRGB(214, 72, 104),
	AccentSoft = Color3.fromRGB(176, 66, 92),
	Text = Color3.fromRGB(236, 236, 241),
	TextDim = Color3.fromRGB(140, 140, 150),
	TextMuted = Color3.fromRGB(96, 96, 106),
	Good = Color3.fromRGB(82, 196, 120),
	Bad = Color3.fromRGB(222, 64, 74),
}

--// text measuring -----------------------------------------------------------
local function charCount(text)
	if utf8 and utf8.len then
		local ok, n = pcall(utf8.len, text)
		if ok and n then
			return n
		end
	end
	return #text
end

local function charSub(text, count)
	if utf8 and utf8.offset then
		local ok, stop = pcall(utf8.offset, text, count + 1)
		if ok and stop then
			return text:sub(1, stop - 1)
		end
	end
	return text:sub(1, count)
end

local function textWidth(text, size)
	return charCount(text) * size * Library.CharWidth
end

local function fitText(text, maxWidth, size)
	text = tostring(text or "")
	if textWidth(text, size) <= maxWidth then
		return text
	end
	local maxChars = math.floor(maxWidth / (size * Library.CharWidth)) - 3
	if maxChars < 1 then
		return ""
	end
	return charSub(text, maxChars) .. "..."
end

local function wrapText(text, maxWidth, size)
	local lines = {}
	for paragraph in (tostring(text or "") .. "\n"):gmatch("(.-)\n") do
		local line = ""
		for word in paragraph:gmatch("%S+") do
			local candidate = line == "" and word or (line .. " " .. word)
			if line ~= "" and textWidth(candidate, size) > maxWidth then
				lines[#lines + 1] = line
				line = word
			else
				line = candidate
			end
		end
		lines[#lines + 1] = fitText(line, maxWidth, size)
	end
	return lines
end

--// keys ---------------------------------------------------------------------
local VirtualKeys = {
	RightShift = 0xA1, LeftShift = 0xA0, Shift = 0x10,
	RightControl = 0xA3, LeftControl = 0xA2, Control = 0x11,
	RightAlt = 0xA5, LeftAlt = 0xA4,
	Insert = 0x2D, Delete = 0x2E, Home = 0x24, End = 0x23,
	PageUp = 0x21, PageDown = 0x22,
	Tab = 0x09, Space = 0x20, Escape = 0x1B, Return = 0x0D, Backspace = 0x08, CapsLock = 0x14,
	Up = 0x26, Down = 0x28, Left = 0x25, Right = 0x27,
	Zero = 0x30, One = 0x31, Two = 0x32, Three = 0x33, Four = 0x34,
	Five = 0x35, Six = 0x36, Seven = 0x37, Eight = 0x38, Nine = 0x39,
}

local function resolveKey(key)
	if key == nil then
		key = "RightShift"
	end
	if type(key) == "number" then
		return { vk = key, name = string.format("0x%X", key) }
	end

	local name
	if type(key) == "string" then
		name = key
	else
		pcall(function()
			name = key.Name -- Enum.KeyCode
		end)
	end
	if not name then
		return resolveKey("RightShift")
	end

	local vk = VirtualKeys[name]
	if not vk then
		local f = name:match("^[Ff](%d+)$")
		if f and tonumber(f) >= 1 and tonumber(f) <= 24 then
			vk = 0x6F + tonumber(f)
		elseif #name == 1 then
			vk = string.byte(name:upper())
		end
	end

	local enum
	pcall(function()
		enum = Enum.KeyCode[name]
	end)

	return { vk = vk, enum = enum, name = name }
end

--// input --------------------------------------------------------------------
local Input = {}

function Input.mouseDown()
	if type(ismouse1pressed) == "function" then
		return ismouse1pressed() == true
	end
	if UserInputService then
		local ok, down = pcall(function()
			return UserInputService:IsMouseButtonPressed(Enum.UserInputType.MouseButton1)
		end)
		return ok and down == true
	end
	return false
end

function Input.keyDown(key)
	if type(iskeypressed) == "function" and key.vk then
		return iskeypressed(key.vk) == true
	end
	if UserInputService and key.enum then
		local ok, down = pcall(function()
			return UserInputService:IsKeyDown(key.enum)
		end)
		return ok and down == true
	end
	return false
end

local mouseObject
function Input.mousePosition()
	if not mouseObject then
		pcall(function()
			mouseObject = Players.LocalPlayer:GetMouse()
		end)
	end
	if mouseObject then
		local ok, x, y = pcall(function()
			return mouseObject.X, mouseObject.Y
		end)
		if ok and x and y then
			return x, y
		end
	end
	if UserInputService then
		local ok, pos = pcall(function()
			return UserInputService:GetMouseLocation()
		end)
		if ok and pos then
			return pos.X, pos.Y
		end
	end
	return 0, 0
end

function Input.focused()
	if type(isrbxactive) == "function" then
		local ok, active = pcall(isrbxactive)
		return not ok or active ~= false
	end
	return true
end

local function viewportSize()
	local ok, size = pcall(function()
		return workspace.CurrentCamera.ViewportSize
	end)
	if ok and size and size.X > 0 then
		return size.X, size.Y
	end
	return 1920, 1080
end

--// layout constants ---------------------------------------------------------
local TOPBAR = 46
local FOOTER = 26
local PAD = 10
local SECTION_HEADER = 30
local ELEMENT_GAP = 6

--==============================================================================
-- Window
--==============================================================================
local Window = {}
Window.__index = Window

local Tab = {}
Tab.__index = Tab

local Section = {}
Section.__index = Section

local function readWidth(size)
	if type(size) == "number" then
		return size
	end
	local width
	pcall(function()
		width = size.X.Offset -- UDim2
	end)
	if type(width) ~= "number" or width <= 0 then
		pcall(function()
			width = size.X -- Vector2 / table
		end)
	end
	if type(width) == "number" and width > 0 then
		return width
	end
	return 470
end

function Library:CreateWindow(config)
	config = config or {}

	-- running the script again replaces the old window instead of stacking a second one
	local env = (type(getgenv) == "function" and getgenv()) or _G
	if env.__UiLibraryWindow then
		pcall(function()
			env.__UiLibraryWindow:Destroy()
		end)
	end

	local theme = {}
	for k, v in pairs(DefaultTheme) do
		theme[k] = v
	end
	if type(config.Theme) == "table" then
		for k, v in pairs(config.Theme) do
			theme[k] = v
		end
	end

	local vw, vh = viewportSize()
	local width = readWidth(config.Size)

	local self = setmetatable({
		Title = config.Title or "UiLibrary",
		Subtitle = config.Subtitle or "",
		Theme = theme,
		Flags = {},
		Visible = true,
		Running = true,

		_toggleKey = resolveKey(config.ToggleKey),
		_width = width,
		_height = 300,
		_x = math.floor(vw / 2 - width / 2),
		_y = math.floor(vh / 2 - 300),
		_tabs = {},
		_currentTab = nil,
		_status = "Disconnected",
		_statusGood = false,
		_notifications = {},

		_pool = { Square = {}, Text = {}, Circle = {} },
		_used = { Square = 0, Text = 0, Circle = 0 },
		_cornerOk = true,

		_mouseX = 0,
		_mouseY = 0,
		_down = false,
		_prevDown = false,
		_clicked = false,
		_prevKey = false,
		_lastFrame = now(),
		_dt = 0,

		_dragging = nil,
		_activeSlider = nil,
		_openDropdown = nil,
		_overlay = nil,
		_lastError = nil,
	}, Window)

	env.__UiLibraryWindow = self
	Library.ActiveWindow = self

	spawnTask(function()
		while self.Running do
			local ok, err = pcall(self._frame, self)
			if not ok and tostring(err) ~= self._lastError then
				self._lastError = tostring(err)
				log("render error:", err)
			end
			waitTask(0.01)
		end
	end)

	return self
end

--// drawing pool -------------------------------------------------------------
function Window:_get(kind)
	local used = self._used[kind] + 1
	self._used[kind] = used
	local object = self._pool[kind][used]
	if not object then
		object = Drawing.new(kind)
		self._pool[kind][used] = object
	end
	object.Visible = true
	return object
end

function Window:_hideUnused()
	for kind, list in pairs(self._pool) do
		for i = self._used[kind] + 1, #list do
			if list[i].Visible then
				list[i].Visible = false
			end
		end
	end
end

function Window:_rect(x, y, w, h, color, z, corner, alpha)
	if w <= 0 or h <= 0 then
		return
	end
	local o = self:_get("Square")
	o.Position = Vector2.new(math.floor(x), math.floor(y))
	o.Size = Vector2.new(math.floor(w), math.floor(h))
	o.Color = color
	o.Filled = true
	o.Thickness = 1
	o.Transparency = alpha or 1
	o.ZIndex = z or 1
	if self._cornerOk then
		local ok = pcall(function()
			o.Corner = corner or 0
		end)
		if not ok then
			self._cornerOk = false
		end
	end
end

-- align: "left" (default), "center" or "right" relative to x
function Window:_text(str, x, y, color, size, z, align, alpha)
	str = tostring(str or "")
	if str == "" then
		return
	end
	size = size or 13
	local o = self:_get("Text")
	if align == "center" then
		x = x - textWidth(str, size) / 2
	elseif align == "right" then
		x = x - textWidth(str, size)
	end
	o.Text = str
	o.Size = size
	o.Font = FONT
	o.Center = false
	o.Outline = false
	o.Color = color
	o.Transparency = alpha or 1
	o.ZIndex = z or 5
	o.Position = Vector2.new(math.floor(x + 0.5), math.floor(y + 0.5))
end

function Window:_circle(x, y, radius, color, z, alpha)
	local o = self:_get("Circle")
	o.Position = Vector2.new(x, y)
	o.Radius = radius
	o.Color = color
	o.Filled = true
	o.Thickness = 1
	o.NumSides = 20
	o.Transparency = alpha or 1
	o.ZIndex = z or 5
end

-- 1px border drawn as a slightly larger rect behind the main one
function Window:_box(x, y, w, h, fill, border, z, corner, alpha)
	self:_rect(x - 1, y - 1, w + 2, h + 2, border, z, corner and corner + 1, alpha)
	self:_rect(x, y, w, h, fill, z + 1, corner, alpha)
end

function Window:_over(x, y, w, h)
	local mx, my = self._mouseX, self._mouseY
	return mx >= x and mx <= x + w and my >= y and my <= y + h
end

-- returns true once for a click inside the area, and consumes it
function Window:_clickIn(x, y, w, h)
	if self._clicked and self:_over(x, y, w, h) then
		self._clicked = false
		return true
	end
	return false
end

--// frame --------------------------------------------------------------------
function Window:_frame()
	local t = now()
	self._dt = math.min(t - self._lastFrame, 0.1)
	self._lastFrame = t

	for kind in pairs(self._used) do
		self._used[kind] = 0
	end

	if not Input.focused() then
		-- game window not focused: hide everything, keep state
		self._prevDown = false
		self:_hideUnused()
		return
	end

	self._mouseX, self._mouseY = Input.mousePosition()
	local down = Input.mouseDown()
	self._clicked = down and not self._prevDown
	self._down = down
	self._prevDown = down

	local keyDown = Input.keyDown(self._toggleKey)
	if keyDown and not self._prevKey then
		self:Toggle()
	end
	self._prevKey = keyDown

	if not down then
		self._dragging = nil
		self._activeSlider = nil
	end

	if self.Visible then
		self:_handleOverlayClick()
		self:_drawWindow()
		self:_drawOverlay()
	else
		self._openDropdown = nil
		self._overlay = nil
	end
	self:_drawNotifications(t)

	self:_hideUnused()
end

--// window body --------------------------------------------------------------
function Window:_layoutColumn(tab, side, colW)
	local total = 0
	local list = {}
	for _, section in ipairs(tab._sections) do
		if section.Side == side then
			local h = section:_height(colW)
			list[#list + 1] = { section = section, h = h }
			total = total + h + PAD
		end
	end
	if total > 0 then
		total = total - PAD
	end
	return list, total
end

function Window:_drawWindow()
	local th = self.Theme
	local W = self._width
	local colW = math.floor((W - PAD * 3) / 2)
	local tab = self._currentTab

	local left, leftH, right, rightH = {}, 0, {}, 0
	if tab then
		left, leftH = self:_layoutColumn(tab, "Left", colW)
		right, rightH = self:_layoutColumn(tab, "Right", colW)
	end
	local H = TOPBAR + 1 + PAD + math.max(leftH, rightH, 60) + PAD + FOOTER
	self._height = H

	-- dragging by the top bar
	if self._dragging then
		self._x = self._mouseX - self._dragging.X
		self._y = self._mouseY - self._dragging.Y
	end
	local x, y = self._x, self._y

	-- frame
	self:_box(x, y, W, H, th.Background, th.Border, 1, 6)

	-- brand
	self:_rect(x + 14, y + 14, 18, 18, th.Accent, 3, 4)
	self:_rect(x + 19, y + 19, 8, 8, th.Background, 4, 2)
	local brandW = math.floor(W * 0.45) - 44
	self:_text(fitText(self.Title, brandW, 14), x + 40, y + 9, th.Text, 14, 5)
	self:_text(fitText(self.Subtitle, brandW, 11), x + 40, y + 26, th.TextDim, 11, 5)

	-- tabs
	local tabsX = x + math.floor(W * 0.45)
	local tabsW = W - math.floor(W * 0.45) - 8
	local count = #self._tabs
	if count > 0 then
		local each = tabsW / count
		for i, t in ipairs(self._tabs) do
			local tx = tabsX + (i - 1) * each
			local selected = t == self._currentTab
			local hover = self:_over(tx, y, each, TOPBAR)
			local label = t.Name
			if t.Icon and t.Icon ~= "" and not tostring(t.Icon):find("rbxasset") then
				label = t.Icon .. " " .. label
			end
			local color = selected and th.Text or (hover and th.Text or th.TextDim)
			self:_text(fitText(label, each - 8, 13), tx + each / 2, y + 16, color, 13, 5, "center")
			if selected then
				self:_rect(tx + 8, y + TOPBAR - 2, each - 16, 2, th.Accent, 5, 1)
			end
			if self:_clickIn(tx, y, each, TOPBAR) then
				self:SelectTab(t)
			end
		end
	end

	-- start dragging when the top bar (outside the tabs) is clicked
	if self:_clickIn(x, y, W, TOPBAR) then
		self._dragging = Vector2.new(self._mouseX - x, self._mouseY - y)
	end

	self:_rect(x, y + TOPBAR, W, 1, th.Border, 3)

	-- columns
	local top = y + TOPBAR + 1 + PAD
	local function drawColumn(list, cx)
		local cy = top
		for _, entry in ipairs(list) do
			entry.section:_draw(self, cx, cy, colW, entry.h)
			cy = cy + entry.h + PAD
		end
	end
	drawColumn(left, x + PAD)
	drawColumn(right, x + PAD * 2 + colW)

	-- footer
	local fy = y + H - FOOTER
	self:_rect(x, fy, W, 1, th.Border, 3)
	self:_circle(x + 15, fy + 13, 3.5, self._statusGood and th.Good or th.Bad, 5)
	self:_text(fitText(self._status, W * 0.6, 12), x + 25, fy + 6, th.TextDim, 12, 5)
	self:_text(self._toggleKey.name .. " to hide", x + W - 12, fy + 6, th.TextMuted, 12, 5, "right")

	-- swallow clicks on the window background so they don't fall through to other logic
	self:_clickIn(x, y, W, H)
end

--// dropdown overlay ---------------------------------------------------------
-- Clicks for the open dropdown list are handled before anything else is drawn,
-- using the list position from the previous frame, so the list sits "on top".
function Window:_handleOverlayClick()
	local o = self._overlay
	if not o or not self._clicked then
		return
	end
	local dropdown = o.dropdown
	if self:_over(o.x, o.y, o.w, o.h) then
		local index = math.floor((self._mouseY - o.y - 2) / o.itemH) + 1
		local option = dropdown._options[index]
		if option ~= nil then
			dropdown:_choose(option)
		end
	elseif not self:_over(o.boxX, o.boxY, o.boxW, o.boxH) then
		-- clicked outside: close and let the click through
		self._openDropdown = nil
		self._overlay = nil
		return
	else
		self._openDropdown = nil
	end
	self._clicked = false
end

function Window:_drawOverlay()
	local dropdown = self._openDropdown
	if not dropdown or not dropdown._box then
		self._overlay = nil
		return
	end
	local th = self.Theme
	local box = dropdown._box
	local itemH = 22
	local n = #dropdown._options
	local h = math.max(n, 1) * itemH + 4
	local x, w = box.x, box.w
	local y = box.y + box.h + 3
	local _, vh = viewportSize()
	if y + h > vh - 4 then
		y = box.y - h - 3 -- not enough room below: open upwards
	end

	self:_box(x, y, w, h, th.Section, th.Border, 40, 4)
	if n == 0 then
		self:_text("No options", x + 8, y + 6, th.TextMuted, 12, 43)
	end
	for i, option in ipairs(dropdown._options) do
		local iy = y + 2 + (i - 1) * itemH
		local selected = dropdown:_isSelected(option)
		if self:_over(x, iy, w, itemH) then
			self:_rect(x + 2, iy, w - 4, itemH, th.ElementHover, 42, 3)
		end
		if selected then
			self:_rect(x + 2, iy + 5, 2, itemH - 10, th.Accent, 43)
		end
		self:_text(fitText(option, w - 20, 12), x + 10, iy + 5, selected and th.Accent or th.Text, 12, 43)
	end

	self._overlay = {
		dropdown = dropdown, x = x, y = y, w = w, h = h, itemH = itemH,
		boxX = box.x, boxY = box.y, boxW = box.w, boxH = box.h,
	}
end

--// notifications ------------------------------------------------------------
function Window:_drawNotifications(t)
	local th = self.Theme
	local list = self._notifications
	for i = #list, 1, -1 do
		if t >= list[i].expires then
			table.remove(list, i)
		end
	end

	local vw, vh = viewportSize()
	local w = 260
	local bottom = vh - 20
	for i = #list, 1, -1 do
		local n = list[i]
		local lines = wrapText(n.text, w - 24, 12)
		local h = 32 + #lines * 15 + 8
		local alpha = clamp((n.expires - t) / 0.3, 0, 1)
		local slide = (1 - clamp((t - n.created) / 0.2, 0, 1)) * 40
		local x = vw - 20 - w + slide
		local y = bottom - h

		self:_box(x, y, w, h, th.Background, th.Border, 60, 4, alpha)
		self:_rect(x, y, 3, h, th.Accent, 62, 0, alpha)
		self:_text(fitText(n.title, w - 24, 13), x + 12, y + 9, th.Text, 13, 63, nil, alpha)
		for li, line in ipairs(lines) do
			self:_text(line, x + 12, y + 28 + (li - 1) * 15, th.TextDim, 12, 63, nil, alpha)
		end
		local progress = clamp((n.expires - t) / n.duration, 0, 1)
		self:_rect(x + 3, y + h - 2, (w - 3) * progress, 2, th.AccentSoft, 63, 0, alpha)

		bottom = y - 8
	end
end

--// public window methods ----------------------------------------------------
function Window:CreateTab(config)
	config = config or {}
	local tab = setmetatable({
		Name = config.Name or ("Tab " .. (#self._tabs + 1)),
		Icon = config.Icon,
		Window = self,
		_sections = {},
	}, Tab)
	self._tabs[#self._tabs + 1] = tab
	if not self._currentTab then
		self._currentTab = tab
	end
	return tab
end

function Window:SelectTab(tab)
	if tab and tab ~= self._currentTab then
		self._currentTab = tab
		self._openDropdown = nil
		self._overlay = nil
	end
end

function Window:Toggle(visible)
	if visible == nil then
		visible = not self.Visible
	end
	self.Visible = visible == true
	if not self.Visible then
		self._openDropdown = nil
		self._overlay = nil
		self._dragging = nil
		self._activeSlider = nil
	end
end

function Window:SetStatus(text, connected)
	self._status = tostring(text or "")
	self._statusGood = connected == true
end

function Window:SetTitle(title, subtitle)
	if title ~= nil then
		self.Title = tostring(title)
	end
	if subtitle ~= nil then
		self.Subtitle = tostring(subtitle)
	end
end

function Window:Notify(title, text, duration)
	duration = tonumber(duration) or 3
	local t = now()
	self._notifications[#self._notifications + 1] = {
		title = tostring(title or ""),
		text = tostring(text or ""),
		duration = duration,
		created = t,
		expires = t + duration,
	}
end

function Window:Destroy()
	self.Running = false
	for _, list in pairs(self._pool) do
		for _, object in ipairs(list) do
			pcall(function()
				object.Visible = false
				object:Remove()
			end)
		end
	end
	self._pool = { Square = {}, Text = {}, Circle = {} }
	local env = (type(getgenv) == "function" and getgenv()) or _G
	if env.__UiLibraryWindow == self then
		env.__UiLibraryWindow = nil
	end
	if Library.ActiveWindow == self then
		Library.ActiveWindow = nil
	end
end

-- Library-level shortcuts that act on the most recent window
for _, name in ipairs({ "Toggle", "SetStatus", "SetTitle", "Notify", "Destroy", "SelectTab", "CreateTab" }) do
	if not Library[name] then
		Library[name] = function(self, ...)
			local window = Library.ActiveWindow
			if window then
				return window[name](window, ...)
			end
		end
	end
end

--==============================================================================
-- Tab / Section
--==============================================================================
function Tab:Select()
	self.Window:SelectTab(self)
end

function Tab:CreateSection(config)
	config = config or {}
	local side = config.Side == "Right" and "Right" or "Left"
	local section = setmetatable({
		Name = config.Name or "Section",
		Side = side,
		Icon = config.Icon,
		Tab = self,
		Window = self.Window,
		_elements = {},
	}, Section)
	self._sections[#self._sections + 1] = section
	return section
end

function Section:_height(colW)
	local h = SECTION_HEADER + 4
	local inner = colW - 20
	for _, el in ipairs(self._elements) do
		h = h + el:_height(inner) + ELEMENT_GAP
	end
	return h + 6
end

function Section:_draw(win, x, y, w, h)
	local th = win.Theme
	win:_box(x, y, w, h, th.Section, th.Border, 6, 4)

	local tx = x + 10
	if self.Icon and self.Icon ~= "" and not tostring(self.Icon):find("rbxasset") then
		win:_text(self.Icon, tx, y + 8, th.Accent, 13, 9)
		tx = tx + textWidth(self.Icon, 13) + 7
	end
	win:_text(fitText(self.Name, x + w - 10 - tx, 13), tx, y + 8, th.Text, 13, 9)
	win:_rect(x + 10, y + SECTION_HEADER - 1, w - 20, 1, th.Border, 8)

	local ey = y + SECTION_HEADER + 4
	local inner = w - 20
	for _, el in ipairs(self._elements) do
		local eh = el:_height(inner)
		el:_draw(win, x + 10, ey, inner, eh)
		ey = ey + eh + ELEMENT_GAP
	end
end

function Section:_add(element)
	element.Section = self
	element.Window = self.Window
	self._elements[#self._elements + 1] = element
	return element
end

function Section:_setFlag(flag, value)
	if flag then
		self.Window.Flags[flag] = value
	end
end

--// label --------------------------------------------------------------------
local Label = {}
Label.__index = Label

function Section:AddLabel(text)
	return self:_add(setmetatable({ Text = tostring(text or "") }, Label))
end

function Label:_height(w)
	return #wrapText(self.Text, w, 12) * 15
end

function Label:_draw(win, x, y, w)
	for i, line in ipairs(wrapText(self.Text, w, 12)) do
		win:_text(line, x, y + (i - 1) * 15, win.Theme.TextDim, 12, 12)
	end
end

function Label:Set(text)
	self.Text = tostring(text or "")
end

--// button -------------------------------------------------------------------
local Button = {}
Button.__index = Button

function Section:AddButton(config)
	config = config or {}
	return self:_add(setmetatable({
		Text = config.Name or "Button",
		Callback = config.Callback,
		_flash = 0,
	}, Button))
end

function Button:_height()
	return 26
end

function Button:_draw(win, x, y, w, h)
	local th = win.Theme
	local hover = win:_over(x, y, w, h)
	if win:_clickIn(x, y, w, h) then
		self._flash = 1
		runCallback(self.Callback)
	end
	self._flash = math.max(0, self._flash - win._dt * 5)

	local fill = hover and th.ElementHover or th.Element
	local border = self._flash > 0 and th.Accent or th.Border
	win:_box(x, y, w, h, fill, border, 10, 4)
	win:_text(fitText(self.Text, w - 16, 13), x + w / 2, y + 6, th.Text, 13, 12, "center")
end

function Button:SetText(text)
	self.Text = tostring(text or "")
end

--// toggle -------------------------------------------------------------------
local Toggle = {}
Toggle.__index = Toggle

function Section:AddToggle(config)
	config = config or {}
	local toggle = self:_add(setmetatable({
		Text = config.Name or "Toggle",
		Value = config.Default == true,
		Flag = config.Flag,
		Callback = config.Callback,
	}, Toggle))
	toggle._anim = toggle.Value and 1 or 0
	self:_setFlag(toggle.Flag, toggle.Value)
	return toggle
end

function Toggle:_height()
	return 22
end

function Toggle:_draw(win, x, y, w, h)
	local th = win.Theme
	local hover = win:_over(x, y, w, h)
	if win:_clickIn(x, y, w, h) then
		self:Set(not self.Value)
	end
	self._anim = lerp(self._anim, self.Value and 1 or 0, math.min(1, win._dt * 16))

	local color = (self.Value or hover) and th.Text or th.TextDim
	win:_text(fitText(self.Text, w - 44, 13), x, y + 4, color, 13, 12)

	local trackW, trackH = 30, 16
	local tx, ty = x + w - trackW, y + (h - trackH) / 2
	local trackColor = self.Value and th.Accent or (hover and th.ElementHover or th.Element)
	win:_box(tx, ty, trackW, trackH, trackColor, self.Value and th.Accent or th.Border, 10, 8)
	win:_rect(tx + 2 + self._anim * (trackW - 16), ty + 2, 12, 12, th.Text, 12, 6)
end

function Toggle:Set(value)
	self.Value = value == true
	self.Section:_setFlag(self.Flag, self.Value)
	runCallback(self.Callback, self.Value)
end

function Toggle:Get()
	return self.Value
end

--// slider -------------------------------------------------------------------
local Slider = {}
Slider.__index = Slider

local function decimalsOf(increment)
	local s = tostring(increment)
	local dot = s:find("%.")
	if not dot then
		return 0
	end
	return #s - dot
end

function Section:AddSlider(config)
	config = config or {}
	local min = tonumber(config.Min) or 0
	local max = tonumber(config.Max) or 100
	if max < min then
		min, max = max, min
	end
	local slider = self:_add(setmetatable({
		Text = config.Name or "Slider",
		Min = min,
		Max = max,
		Increment = tonumber(config.Increment) or 1,
		Suffix = config.Suffix or "",
		Flag = config.Flag,
		Callback = config.Callback,
	}, Slider))
	slider.Value = slider:_round(tonumber(config.Default) or min)
	self:_setFlag(slider.Flag, slider.Value)
	return slider
end

function Slider:_round(value)
	local inc = self.Increment
	if inc <= 0 then
		inc = 1
	end
	value = clamp(value, self.Min, self.Max)
	value = self.Min + math.floor((value - self.Min) / inc + 0.5) * inc
	value = clamp(value, self.Min, self.Max)
	local d = decimalsOf(inc)
	return tonumber(string.format("%." .. d .. "f", value))
end

function Slider:_format()
	local d = decimalsOf(self.Increment)
	return string.format("%." .. d .. "f", self.Value) .. self.Suffix
end

function Slider:_height()
	return 36
end

function Slider:_draw(win, x, y, w)
	local th = win.Theme
	local barY, barH = y + 22, 6

	if win:_clickIn(x, y + 14, w, 22) then
		win._activeSlider = self
	end
	if win._activeSlider == self and win._down then
		local pct = clamp((win._mouseX - x) / w, 0, 1)
		self:Set(self.Min + (self.Max - self.Min) * pct)
	end

	local valueText = self:_format()
	win:_text(fitText(self.Text, w - textWidth(valueText, 12) - 10, 13), x, y, th.Text, 13, 12)
	win:_text(valueText, x + w, y + 1, th.TextDim, 12, 12, "right")

	local range = self.Max - self.Min
	local pct = range > 0 and (self.Value - self.Min) / range or 0
	local hover = win:_over(x, y + 14, w, 22) or win._activeSlider == self
	win:_rect(x, barY, w, barH, hover and th.ElementHover or th.Element, 10, 3)
	win:_rect(x, barY, math.max(barH, w * pct), barH, th.Accent, 11, 3)
	win:_rect(x + w * pct - 5, barY - 2, 10, 10, th.Text, 12, 5)
end

function Slider:Set(value, silent)
	value = self:_round(tonumber(value) or self.Min)
	if value == self.Value then
		return
	end
	self.Value = value
	self.Section:_setFlag(self.Flag, value)
	if not silent then
		runCallback(self.Callback, value)
	end
end

function Slider:Get()
	return self.Value
end

--// dropdown -----------------------------------------------------------------
local Dropdown = {}
Dropdown.__index = Dropdown

local function copyList(list)
	local out = {}
	for i, v in ipairs(list or {}) do
		out[i] = v
	end
	return out
end

function Section:AddDropdown(config)
	config = config or {}
	local dropdown = self:_add(setmetatable({
		Text = config.Name or "Dropdown",
		Multi = config.Multi == true,
		Flag = config.Flag,
		Callback = config.Callback,
		_options = copyList(config.Options),
	}, Dropdown))

	if dropdown.Multi then
		local default = config.Default
		if type(default) ~= "table" then
			default = default ~= nil and { default } or {}
		end
		dropdown.Value = copyList(default)
	else
		dropdown.Value = config.Default
	end
	self:_setFlag(dropdown.Flag, dropdown:Get())
	return dropdown
end

function Dropdown:_isSelected(option)
	if self.Multi then
		for _, v in ipairs(self.Value) do
			if v == option then
				return true
			end
		end
		return false
	end
	return self.Value == option
end

function Dropdown:_display()
	if self.Multi then
		if #self.Value == 0 then
			return "--"
		end
		local parts = {}
		for i, v in ipairs(self.Value) do
			parts[i] = tostring(v)
		end
		return table.concat(parts, ", ")
	end
	if self.Value == nil then
		return "--"
	end
	return tostring(self.Value)
end

function Dropdown:_choose(option)
	if self.Multi then
		local list = copyList(self.Value)
		local found
		for i, v in ipairs(list) do
			if v == option then
				found = i
				break
			end
		end
		if found then
			table.remove(list, found)
		else
			list[#list + 1] = option
		end
		self:Set(list)
	else
		self:Set(option)
		self.Window._openDropdown = nil
	end
end

function Dropdown:_height()
	return 44
end

function Dropdown:_draw(win, x, y, w)
	local th = win.Theme
	local boxY, boxH = y + 17, 26
	self._box = { x = x, y = boxY, w = w, h = boxH }

	local open = win._openDropdown == self
	if win:_clickIn(x, boxY, w, boxH) then
		win._openDropdown = open and nil or self
		open = not open
	end

	win:_text(fitText(self.Text, w, 13), x, y, th.Text, 13, 12)
	local hover = win:_over(x, boxY, w, boxH)
	win:_box(x, boxY, w, boxH, hover and th.ElementHover or th.Element, open and th.Accent or th.Border, 10, 4)
	local display = self:_display()
	win:_text(fitText(display, w - 30, 12), x + 8, boxY + 7, display == "--" and th.TextMuted or th.Text, 12, 12)
	win:_text(open and "^" or "v", x + w - 10, boxY + 6, th.TextDim, 12, 12, "right")
end

function Dropdown:Set(value)
	if self.Multi then
		if type(value) ~= "table" then
			value = value ~= nil and { value } or {}
		end
		self.Value = copyList(value)
	else
		self.Value = value
	end
	self.Section:_setFlag(self.Flag, self:Get())
	runCallback(self.Callback, self:Get())
end

function Dropdown:Get()
	if self.Multi then
		return copyList(self.Value)
	end
	return self.Value
end

function Dropdown:Refresh(options, keepSelection)
	self._options = copyList(options)
	if keepSelection then
		-- drop selections that no longer exist
		if self.Multi then
			local kept = {}
			for _, v in ipairs(self.Value) do
				for _, o in ipairs(self._options) do
					if o == v then
						kept[#kept + 1] = v
						break
					end
				end
			end
			self.Value = kept
		elseif not self:_isSelectedIn(self._options) then
			self.Value = nil
		end
	else
		self.Value = self.Multi and {} or nil
	end
	self.Section:_setFlag(self.Flag, self:Get())
end

function Dropdown:_isSelectedIn(options)
	for _, o in ipairs(options) do
		if o == self.Value then
			return true
		end
	end
	return false
end

-- Matcha can drop the value a loadstring chunk returns, so also expose the
-- library globally. test.lua falls back to this.
_G.UiLibrary = Library
pcall(function()
	if type(getgenv) == "function" then
		getgenv().UiLibrary = Library
	end
end)

return Library
