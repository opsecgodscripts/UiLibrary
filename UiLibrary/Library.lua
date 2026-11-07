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
	  Library:CreateWindow({ Title, Subtitle, ToggleKey, Size, Theme, Font, Logo })  -> Window
	    Logo:      link to a PNG / JPG / WebP image, drawn 20 x 20 in the top-left
	    Font:      "UI" (default), "Plex", "System" or "Monospace"
	    Theme:     "Default", "Tung", or a table of colors
	    MaxFps:    starting FPS cap (default: unlimited); changeable in the UI tab
	  Window:SetFpsCap(number or nil)  -- caps the UI's redraws, and the game via setfpscap if available
	    ToggleKey: "RightShift", "Insert", "F1", "K" ... or a virtual-key number (0xA1)
	               or an Enum.KeyCode if the executor has Enum.
	    Size:      Vector2/UDim2 (default 450 x 557) or just a width. The window grows
	               taller only if a tab's sections don't fit.
	    Window:CreateTab({ Name, Icon })            -> Tab
	    Window:SetStatus(text, connected)           -- footer dot + text
	    Window:SetTitle(title, subtitle)
	    Window:Notify(title, text, duration)
	    Window:SelectTab(tab)
	    Window:Toggle([visible])
	    Window:Destroy()
	    Window.Flags[flag]                          -- current value of every flagged element

	  Tab:CreateSection({ Name, Side = "Left" | "Right" }) -> Section
	  Tab:Select()

	  Section:AddToggle({ Name, Default, Flag, Callback })              -> :Set(bool) :Get()
	  Section:AddButton({ Name, Callback })                             -> :SetText(text)
	  Section:AddLabel(text)                                            -> :Set(text)
	  Section:AddSlider({ Name, Min, Max, Default, Increment, Suffix, Flag, Callback })
	                                                                    -> :Set(number) :Get()
	  Section:AddDropdown({ Name, Options, Default, Multi, Flag, Callback })
	                                                                    -> :Set(value) :Get() :Refresh(options)
	  Section:AddTextbox({ Name, Default, Placeholder, Numeric, MaxLength, ClearOnFocus, Live, Flag, Callback })
	                                                                    -> :Set(text) :Get()
	    Callback(text, submitted) fires on Enter or clicking away (every keystroke if Live = true).
	    Escape cancels the edit. Needs iskeypressed (Matcha has it).
	  Section:AddKeybind({ Name, Default, Mode = "Press" | "Toggle" | "Hold", Menu, Flag, Callback, ChangedCallback })
	                                                                    -> :Set(key) :Get() :GetState()
	    Click the key box, then press a key. Escape cancels, Backspace clears.
	    Menu = true makes it the show / hide key for the window.
	  Section:AddToggle({ ..., Keybind = "F", KeybindMode = "Toggle" | "Hold" })
	    adds a key box next to the checkbox; the key flips the toggle even when the UI is hidden.

	  Window:SetTheme("Tung" | "Default" | table)    Window:SetToggleKey(key)

	Saving
	  Every element with a Flag is saved to <Folder>/settings.json and restored the next
	  time the script runs (Folder defaults to the window Title). Pass Save = false on an
	  element to skip it, or AutoSave = false to CreateWindow to turn this off.
	  Window:SaveConfig(name) :LoadConfig(name) :RenameConfig(old, new) :DeleteConfig(name)
	  Window:ListConfigs()     Window:SaveSettings()
	  Window:AddConfigSection(tab, side)  -- ready-made Save / Load / Rename / Delete / Autoload UI
	  Window:OpenAnimationTracker()       -- small window that lists animations a character plays
	    (also a button in the UI tab). Reads animations with Library.AnimationProvider(model)
	    if set, else memory_read + offsets (Matcha), else GetPlayingAnimationTracks.
	    Library.TrackerIgnore = { ["id"] = true } hides IDs; Library.AnimationNames = { ["id"] = "M1" }
	    shows names. "Show ESP" draws the target's name and distance above its head and its
	    playing animations (with time) below its feet.
	  Section:AddList({ Rows, Empty, OnClick }) -> :SetItems({ { Text, Right, Value }, ... })
	  element:SetVisible(bool) on any element

	Built-in UI tab
	  Every window gets a last tab ("UI") with Theme, Font, Menu Key, FPS Cap, Show Performance
	  (a "Title | fps | ping" bar, draggable while the UI is open), Notifications,
	  Hide UI, Unload and Configs. These are saved between runs but not stored in
	  configs. CreateWindow options: UniversalTab = false to leave it out, or
	  UniversalTab = { Name = "Settings", Icon = "@" }; OnUnload = function() end
	  runs when Unload is pressed. Window.UniversalTab is the tab, so you can add
	  your own sections to it.

	Callbacks only fire when the user changes a value or you call :Set(), not when
	the element is created.

	Icons are short text. Stick to plain ASCII (">", "+", "*", "#") because the
	Drawing font may not have symbols or emoji. Image icons are not supported.
]]

local Library = {}
Library.Version = "2.0.0"
Library.CharWidth = nil -- override the estimated character width (fraction of text size) if text looks off

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

-- Drawing fonts: UI = 0, System = 1, Plex = 2, Monospace = 3
local FontIds = { UI = 0, System = 1, Plex = 2, Monospace = 3 }
pcall(function()
	if Drawing.Fonts then
		for name in pairs(FontIds) do
			if type(Drawing.Fonts[name]) == "number" then
				FontIds[name] = Drawing.Fonts[name]
			end
		end
	end
end)
local FONT = FontIds.UI

-- names for the Font dropdown: the standard four first, then anything extra the executor has
local function fontNames()
	local names = { "UI", "System", "Plex", "Monospace" }
	local seen = { UI = true, System = true, Plex = true, Monospace = true }
	pcall(function()
		local extra = {}
		for name, id in pairs(Drawing.Fonts) do
			if type(name) == "string" and type(id) == "number" and not seen[name] then
				FontIds[name] = id
				extra[#extra + 1] = name
			end
		end
		table.sort(extra)
		for _, name in ipairs(extra) do
			names[#names + 1] = name
		end
	end)
	return names
end

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

-- reads object[name] without erroring
local function prop(object, name)
	if object == nil then
		return nil
	end
	local ok, v = pcall(function()
		return object[name]
	end)
	return ok and v or nil
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
	Background = Color3.fromRGB(12, 11, 16),
	Topbar = Color3.fromRGB(23, 23, 28),
	TabActive = Color3.fromRGB(7, 8, 12),
	Footer = Color3.fromRGB(25, 24, 30),
	Section = Color3.fromRGB(16, 16, 20),
	SectionHeader = Color3.fromRGB(23, 23, 28),
	Element = Color3.fromRGB(28, 28, 32),
	ElementHover = Color3.fromRGB(36, 36, 41),
	Border = Color3.fromRGB(28, 28, 33),
	Accent = Color3.fromRGB(214, 72, 104),
	AccentSoft = Color3.fromRGB(150, 52, 76),
	Text = Color3.fromRGB(238, 238, 242),
	TextDim = Color3.fromRGB(128, 128, 136),
	TextMuted = Color3.fromRGB(90, 90, 98),
	Good = Color3.fromRGB(82, 196, 120),
	Bad = Color3.fromRGB(222, 64, 74),
}

-- built-in themes: pass Theme = "Tung" (or a table of colors) to CreateWindow,
-- or call Window:SetTheme("Tung") at any time
Library.Themes = {
	Default = DefaultTheme,
	Tung = {
		Background = Color3.fromRGB(18, 12, 8),
		Topbar = Color3.fromRGB(36, 24, 15),
		TabActive = Color3.fromRGB(12, 8, 5),
		Footer = Color3.fromRGB(38, 25, 16),
		Section = Color3.fromRGB(26, 17, 11),
		SectionHeader = Color3.fromRGB(40, 27, 17),
		Element = Color3.fromRGB(46, 31, 20),
		ElementHover = Color3.fromRGB(60, 40, 26),
		Border = Color3.fromRGB(54, 37, 24),
		Accent = Color3.fromRGB(206, 122, 52),
		AccentSoft = Color3.fromRGB(140, 76, 30),
		Text = Color3.fromRGB(246, 232, 212),
		TextDim = Color3.fromRGB(172, 146, 118),
		TextMuted = Color3.fromRGB(120, 98, 76),
		Good = Color3.fromRGB(120, 196, 90),
		Bad = Color3.fromRGB(222, 76, 60),
	},
}

local function rgb(r, g, b)
	return Color3.fromRGB(r, g, b)
end

local function addTheme(name, c)
	Library.Themes[name] = c
end

addTheme("Dark", {
	Background = rgb(7, 7, 8), Topbar = rgb(17, 17, 19), TabActive = rgb(3, 3, 4), Footer = rgb(17, 17, 19),
	Section = rgb(12, 12, 14), SectionHeader = rgb(21, 21, 24), Element = rgb(27, 27, 30), ElementHover = rgb(36, 36, 40),
	Border = rgb(30, 30, 33), Accent = rgb(130, 140, 160), AccentSoft = rgb(80, 86, 100),
	Text = rgb(236, 236, 238), TextDim = rgb(138, 138, 144), TextMuted = rgb(92, 92, 98),
})
addTheme("Light", {
	Background = rgb(226, 226, 232), Topbar = rgb(246, 246, 249), TabActive = rgb(214, 214, 222), Footer = rgb(240, 240, 244),
	Section = rgb(244, 244, 247), SectionHeader = rgb(232, 232, 238), Element = rgb(220, 220, 228), ElementHover = rgb(208, 208, 218),
	Border = rgb(204, 204, 212), Accent = rgb(60, 110, 230), AccentSoft = rgb(140, 175, 245), AccentText = rgb(255, 255, 255),
	Text = rgb(24, 24, 30), TextDim = rgb(92, 92, 104), TextMuted = rgb(140, 140, 152),
	Good = rgb(40, 160, 80), Bad = rgb(210, 50, 60),
})
addTheme("Midnight", {
	Background = rgb(9, 11, 21), Topbar = rgb(18, 22, 38), TabActive = rgb(5, 7, 15), Footer = rgb(18, 22, 38),
	Section = rgb(13, 16, 29), SectionHeader = rgb(22, 27, 46), Element = rgb(28, 34, 56), ElementHover = rgb(36, 44, 70),
	Border = rgb(30, 36, 60), Accent = rgb(92, 132, 255), AccentSoft = rgb(60, 88, 188),
	Text = rgb(228, 232, 246), TextDim = rgb(130, 140, 172), TextMuted = rgb(88, 96, 124),
})
addTheme("Ocean", {
	Background = rgb(7, 14, 18), Topbar = rgb(14, 26, 32), TabActive = rgb(4, 9, 12), Footer = rgb(14, 26, 32),
	Section = rgb(10, 20, 25), SectionHeader = rgb(18, 33, 41), Element = rgb(22, 40, 50), ElementHover = rgb(30, 52, 64),
	Border = rgb(24, 44, 54), Accent = rgb(38, 192, 212), AccentSoft = rgb(28, 126, 140),
	Text = rgb(224, 240, 245), TextDim = rgb(124, 160, 170), TextMuted = rgb(84, 110, 120),
})
addTheme("Forest", {
	Background = rgb(9, 14, 11), Topbar = rgb(18, 27, 20), TabActive = rgb(5, 9, 6), Footer = rgb(18, 27, 20),
	Section = rgb(13, 20, 15), SectionHeader = rgb(22, 33, 25), Element = rgb(28, 41, 31), ElementHover = rgb(36, 53, 40),
	Border = rgb(30, 45, 34), Accent = rgb(92, 192, 110), AccentSoft = rgb(56, 130, 74),
	Text = rgb(230, 241, 232), TextDim = rgb(134, 160, 140), TextMuted = rgb(90, 110, 95),
})
addTheme("Amethyst", {
	Background = rgb(13, 9, 20), Topbar = rgb(26, 18, 37), TabActive = rgb(8, 5, 13), Footer = rgb(26, 18, 37),
	Section = rgb(19, 13, 28), SectionHeader = rgb(32, 22, 45), Element = rgb(40, 28, 56), ElementHover = rgb(52, 36, 71),
	Border = rgb(44, 30, 61), Accent = rgb(162, 102, 255), AccentSoft = rgb(110, 70, 182),
	Text = rgb(238, 230, 248), TextDim = rgb(155, 140, 176), TextMuted = rgb(104, 94, 126),
})
addTheme("Crimson", {
	Background = rgb(15, 7, 8), Topbar = rgb(30, 14, 16), TabActive = rgb(9, 4, 5), Footer = rgb(30, 14, 16),
	Section = rgb(22, 10, 12), SectionHeader = rgb(37, 17, 19), Element = rgb(47, 22, 25), ElementHover = rgb(61, 28, 32),
	Border = rgb(51, 24, 27), Accent = rgb(226, 52, 62), AccentSoft = rgb(150, 36, 43),
	Text = rgb(246, 230, 231), TextDim = rgb(170, 134, 137), TextMuted = rgb(114, 90, 92),
})

local function buildTheme(theme)
	local out = {}
	for k, v in pairs(DefaultTheme) do
		out[k] = v
	end
	if type(theme) == "string" then
		theme = Library.Themes[theme]
	end
	if type(theme) == "table" then
		for k, v in pairs(theme) do
			out[k] = v
		end
	end
	return out
end

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

local function charWidth()
	if type(Library.CharWidth) == "number" then
		return Library.CharWidth
	end
	-- measured from Matcha screenshots (about 6.5px per character at size 13)
	return FONT == FontIds.Monospace and 0.72 or 0.5
end

-- relative letter widths for the proportional fonts, calibrated on Matcha screenshots
local LetterWidth = {}
for c in ("abcdeghknopqsuvxyz"):gmatch(".") do
	LetterWidth[c] = 0.52
end
for c in ("ijl'|!.,:;"):gmatch(".") do
	LetterWidth[c] = 0.25
end
for c in ("tfr()[]{}"):gmatch(".") do
	LetterWidth[c] = 0.32
end
LetterWidth[" "] = 0.28
LetterWidth.m, LetterWidth.w = 0.78, 0.72
for c in ("ABCDEFGHJKLNOPQRSTUVXYZ"):gmatch(".") do
	LetterWidth[c] = 0.62
end
LetterWidth.I, LetterWidth.M, LetterWidth.W = 0.28, 0.78, 0.85
for c in ("0123456789"):gmatch(".") do
	LetterWidth[c] = 0.55
end

local function textWidth(text, size)
	if type(Library.CharWidth) == "number" or FONT == FontIds.Monospace then
		return charCount(text) * size * charWidth()
	end
	local total = 0
	for i = 1, #text do
		local b = text:byte(i)
		if b < 128 then
			total = total + (LetterWidth[string.char(b)] or 0.55)
		elseif b >= 192 then
			total = total + 0.6 -- first byte of a non-ASCII character
		end
	end
	return total * size * 0.9
end

local FIT_MARGIN = 1.12 -- estimates can be a bit short for wide letters, so fit with some slack

local function fitText(text, maxWidth, size)
	text = tostring(text or "")
	maxWidth = maxWidth / FIT_MARGIN
	if textWidth(text, size) <= maxWidth then
		return text
	end
	local count = charCount(text)
	local lo, hi = 0, count
	while lo < hi do -- longest prefix that fits with "..."
		local mid = math.floor((lo + hi + 1) / 2)
		if textWidth(charSub(text, mid) .. "...", size) <= maxWidth then
			lo = mid
		else
			hi = mid - 1
		end
	end
	if lo < 1 then
		return ""
	end
	return charSub(text, lo) .. "..."
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

local KeyNames = {
	[0xA1] = "RShift", [0xA0] = "LShift", [0x10] = "Shift",
	[0xA3] = "RCtrl", [0xA2] = "LCtrl", [0x11] = "Ctrl",
	[0xA5] = "RAlt", [0xA4] = "LAlt", [0x12] = "Alt",
	[0x2D] = "Insert", [0x2E] = "Delete", [0x24] = "Home", [0x23] = "End",
	[0x21] = "PgUp", [0x22] = "PgDn", [0x09] = "Tab", [0x20] = "Space",
	[0x1B] = "Esc", [0x0D] = "Enter", [0x08] = "Back", [0x14] = "Caps",
	[0x26] = "Up", [0x28] = "Down", [0x25] = "Left", [0x27] = "Right",
	[0x04] = "MB3", [0x05] = "MB4", [0x06] = "MB5",
	[0xBA] = ";", [0xBB] = "=", [0xBC] = ",", [0xBD] = "-", [0xBE] = ".", [0xBF] = "/",
	[0xC0] = "`", [0xDB] = "[", [0xDC] = "\\", [0xDD] = "]", [0xDE] = "'",
}
for c = 0x41, 0x5A do
	KeyNames[c] = string.char(c)
end
for d = 0, 9 do
	KeyNames[0x30 + d] = tostring(d)
	KeyNames[0x60 + d] = "Num" .. d
end
for f = 1, 24 do
	KeyNames[0x6F + f] = "F" .. f
end

local KeyNameToVk = {}
for vk, name in pairs(KeyNames) do
	KeyNameToVk[name:upper()] = vk
end

local function keyName(vk)
	return KeyNames[vk] or string.format("0x%X", vk)
end

local function resolveKey(key)
	if key == nil then
		key = "RightShift"
	end
	if type(key) == "number" then
		return { vk = key, name = keyName(key) }
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

	local vk = VirtualKeys[name] or KeyNameToVk[name:upper()]
	if not vk then
		local hex = name:match("^0[xX](%x+)$")
		vk = hex and tonumber(hex, 16)
	end
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

	return { vk = vk, enum = enum, name = vk and keyName(vk) or name }
end

-- nil / false / "None" mean no key
local function resolveOptionalKey(key)
	if key == nil or key == false or key == "" or key == "None" then
		return nil
	end
	return resolveKey(key)
end

--// typing -------------------------------------------------------------------
-- virtual-key code -> { normal, with shift }
local TypingKeys = {}
for c = 0x41, 0x5A do
	TypingKeys[c] = { string.char(c + 32), string.char(c) }
end
local digitShift = { ")", "!", "@", "#", "$", "%", "^", "&", "*", "(" }
for d = 0, 9 do
	TypingKeys[0x30 + d] = { tostring(d), digitShift[d + 1] }
	TypingKeys[0x60 + d] = { tostring(d), tostring(d) } -- numpad
end
TypingKeys[0x20] = { " ", " " }
TypingKeys[0xBA] = { ";", ":" }
TypingKeys[0xBB] = { "=", "+" }
TypingKeys[0xBC] = { ",", "<" }
TypingKeys[0xBD] = { "-", "_" }
TypingKeys[0xBE] = { ".", ">" }
TypingKeys[0xBF] = { "/", "?" }
TypingKeys[0xC0] = { "`", "~" }
TypingKeys[0xDB] = { "[", "{" }
TypingKeys[0xDC] = { "\\", "|" }
TypingKeys[0xDD] = { "]", "}" }
TypingKeys[0xDE] = { "'", '"' }
TypingKeys[0x6A] = { "*", "*" }
TypingKeys[0x6B] = { "+", "+" }
TypingKeys[0x6D] = { "-", "-" }
TypingKeys[0x6E] = { ".", "." }
TypingKeys[0x6F] = { "/", "/" }

local VK_BACK, VK_ENTER, VK_ESCAPE = 0x08, 0x0D, 0x1B

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

function Input.vk(code)
	if type(iskeypressed) == "function" then
		local ok, down = pcall(iskeypressed, code)
		return ok and down == true
	end
	return false
end

function Input.shift()
	return Input.vk(0x10) or Input.vk(0xA0) or Input.vk(0xA1)
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

--// json (small, so it works without HttpService) ------------------------------
local Json = {}

local function jsonString(str)
	return '"' .. str:gsub('[%c"\\]', function(c)
		local map = { ['"'] = '\\"', ["\\"] = "\\\\", ["\n"] = "\\n", ["\r"] = "\\r", ["\t"] = "\\t" }
		return map[c] or string.format("\\u%04x", c:byte())
	end) .. '"'
end

function Json.encode(value)
	local t = type(value)
	if t == "string" then
		return jsonString(value)
	elseif t == "number" then
		if value ~= value or value == math.huge or value == -math.huge then
			return "0"
		end
		if value == math.floor(value) and math.abs(value) < 1e15 then
			return string.format("%d", value)
		end
		return string.format("%.14g", value)
	elseif t == "boolean" then
		return tostring(value)
	elseif t == "table" then
		local n = #value
		local isArray = true
		for k in pairs(value) do
			if type(k) ~= "number" or k < 1 or k > n or k % 1 ~= 0 then
				isArray = false
				break
			end
		end
		local parts = {}
		if isArray then
			for i = 1, n do
				parts[i] = Json.encode(value[i])
			end
			return "[" .. table.concat(parts, ",") .. "]"
		end
		local keys = {}
		for k in pairs(value) do
			keys[#keys + 1] = tostring(k)
		end
		table.sort(keys)
		for _, k in ipairs(keys) do
			local v = value[k]
			if v == nil then
				v = value[tonumber(k)]
			end
			parts[#parts + 1] = jsonString(k) .. ":" .. Json.encode(v)
		end
		return "{" .. table.concat(parts, ",") .. "}"
	end
	return "null"
end

function Json.decode(text)
	-- returns nil on bad input; never calls error() (Matcha prints those even inside pcall)
	if type(text) ~= "string" or not text:find("%S") then
		return nil
	end
	local pos = 1
	local failed = false
	local function skip()
		pos = text:find("[^ \t\r\n]", pos) or (#text + 1)
	end
	local parseValue
	local function parseString()
		pos = pos + 1
		local out = {}
		while not failed do
			local c = text:sub(pos, pos)
			if c == "" then
				failed = true
			elseif c == '"' then
				pos = pos + 1
				break
			elseif c == "\\" then
				local e = text:sub(pos + 1, pos + 1)
				local map = { n = "\n", r = "\r", t = "\t", b = "\b", f = "\f", ["/"] = "/", ["\\"] = "\\", ['"'] = '"' }
				if e == "u" then
					local code = tonumber(text:sub(pos + 2, pos + 5), 16) or 63
					out[#out + 1] = code < 128 and string.char(code) or "?"
					pos = pos + 6
				else
					out[#out + 1] = map[e] or e
					pos = pos + 2
				end
			else
				out[#out + 1] = c
				pos = pos + 1
			end
		end
		return table.concat(out)
	end
	function parseValue()
		if failed then
			return nil
		end
		skip()
		local c = text:sub(pos, pos)
		if c == "{" then
			pos = pos + 1
			local obj = {}
			skip()
			if text:sub(pos, pos) == "}" then
				pos = pos + 1
				return obj
			end
			while not failed do
				skip()
				if text:sub(pos, pos) ~= '"' then
					failed = true
					return nil
				end
				local key = parseString()
				skip()
				if text:sub(pos, pos) ~= ":" then
					failed = true
					return nil
				end
				pos = pos + 1
				obj[key] = parseValue()
				skip()
				local d = text:sub(pos, pos)
				pos = pos + 1
				if d == "}" then
					return obj
				elseif d ~= "," then
					failed = true
				end
			end
			return nil
		elseif c == "[" then
			pos = pos + 1
			local arr = {}
			skip()
			if text:sub(pos, pos) == "]" then
				pos = pos + 1
				return arr
			end
			while not failed do
				arr[#arr + 1] = parseValue()
				skip()
				local d = text:sub(pos, pos)
				pos = pos + 1
				if d == "]" then
					return arr
				elseif d ~= "," then
					failed = true
				end
			end
			return nil
		elseif c == '"' then
			return parseString()
		elseif text:sub(pos, pos + 3) == "true" then
			pos = pos + 4
			return true
		elseif text:sub(pos, pos + 4) == "false" then
			pos = pos + 5
			return false
		elseif text:sub(pos, pos + 3) == "null" then
			pos = pos + 4
			return nil
		end
		local num = text:match("^-?%d+%.?%d*[eE]?[-+]?%d*", pos)
		if not num or num == "" then
			failed = true
			return nil
		end
		pos = pos + #num
		return tonumber(num)
	end
	local result = parseValue()
	if failed then
		return nil
	end
	return result
end

--// storage: files when the executor has them, otherwise memory ---------------
-- (memory survives re-executing in the same game session, files survive restarts)
local Storage = {}
local memoryFiles
do
	local env = (type(getgenv) == "function" and getgenv()) or _G
	env.__UiLibraryFiles = env.__UiLibraryFiles or {}
	memoryFiles = env.__UiLibraryFiles
end
local hasFiles = type(writefile) == "function" and type(readfile) == "function"
local warnedNoFiles = false

function Storage.folder(path)
	if not hasFiles or type(makefolder) ~= "function" then
		return
	end
	pcall(function()
		if type(isfolder) == "function" and isfolder(path) then
			return
		end
		makefolder(path)
	end)
end

function Storage.write(path, content)
	memoryFiles[path] = content
	if hasFiles then
		local ok, err = pcall(writefile, path, content)
		if ok then
			return true
		end
		log("couldn't write", path, err)
	elseif not warnedNoFiles then
		warnedNoFiles = true
		log("this executor has no writefile: settings are kept until you leave the game")
	end
	return false
end

function Storage.read(path)
	if hasFiles then
		local ok, data = pcall(function()
			if type(isfile) == "function" and not isfile(path) then
				return nil
			end
			return readfile(path)
		end)
		if ok and type(data) == "string" and data ~= "" then
			return data
		end
	end
	return memoryFiles[path]
end

function Storage.delete(path)
	memoryFiles[path] = nil
	if hasFiles and type(delfile) == "function" then
		pcall(delfile, path)
	elseif hasFiles then
		pcall(writefile, path, "")
	end
end

local function cleanName(name)
	name = tostring(name or ""):gsub("[^%w _%-]", ""):gsub("^%s+", ""):gsub("%s+$", "")
	return name:sub(1, 40)
end

--// images -------------------------------------------------------------------
-- Drawing images take the raw bytes of a PNG, JPG or WebP file
local function isImageData(data)
	if type(data) ~= "string" or #data < 12 then
		return false
	end
	if data:sub(1, 8) == "\137PNG\r\n\26\n" then
		return true
	end
	if data:byte(1) == 255 and data:byte(2) == 216 and data:byte(3) == 255 then
		return true
	end
	return data:sub(1, 4) == "RIFF" and data:sub(9, 12) == "WEBP"
end

-- source: a URL to a PNG/JPG/WebP, or the raw image bytes
local function loadImage(source, done)
	if isImageData(source) then
		done(source)
		return
	end
	if type(source) ~= "string" or not source:match("^https?://") then
		log("Logo must be a link to a PNG, JPG or WebP file")
		return
	end
	spawnTask(function()
		local ok, data = pcall(function()
			return game:HttpGet(source)
		end)
		if ok and isImageData(data) then
			done(data)
		else
			log("couldn't load image from", source)
		end
	end)
end

--// layout constants ---------------------------------------------------------
-- sizes match the reference layout (450 x 557 window)
local TOPBAR = 38
local FOOTER = 20
local EDGE = 10 -- space between window edge and sections
local PAD = 10 -- space between columns and between stacked sections
local SECTION_HEADER = 28
local ELEMENT_GAP = 10
local INSET = 12 -- space inside a section, left and right
local LABEL_GAP = 19 -- label top to its box / bar
local TEXT = 13 -- element labels (renders about 7px tall in Matcha)
local SMALL = 12 -- values, footer

--==============================================================================
-- Window
--==============================================================================
local Window = {}
Window.__index = Window

local Tab = {}
Tab.__index = Tab

local newKeybind -- defined with the keybind element below

local Section = {}
Section.__index = Section

local function readSize(size)
	if type(size) == "number" then
		return size, 557
	end
	local w, h
	-- Vector2 / { X = , Y = } first: plain numbers, nothing that can error
	local x = prop(size, "X")
	if type(x) == "number" then
		w, h = x, prop(size, "Y")
	elseif x ~= nil then
		w, h = prop(x, "Offset"), prop(prop(size, "Y"), "Offset") -- UDim2
	end
	if type(w) ~= "number" or w <= 0 then
		w = 450
	end
	if type(h) ~= "number" or h <= 0 then
		h = 557
	end
	return w, h
end

function Library:CreateWindow(config)
	config = config or {}

	-- running the script again replaces the old window instead of stacking a second one
	local env = (type(getgenv) == "function" and getgenv()) or _G
	for _, holder in ipairs(config.Mini and {} or { env, _G, type(shared) == "table" and shared or {} }) do
		local old = rawget(holder, "__UiLibraryWindow")
		if old then
			pcall(function()
				old:Destroy()
			end)
			rawset(holder, "__UiLibraryWindow", nil)
		end
	end

	local theme = buildTheme(config.Theme)

	if config.Font ~= nil then
		FONT = FontIds[config.Font] or (type(config.Font) == "number" and config.Font) or FONT
	end

	local vw, vh = viewportSize()
	local width, minHeight = readSize(config.Size)

	local self = setmetatable({
		Title = config.Title or "UiLibrary",
		Subtitle = config.Subtitle or "",
		Theme = theme,
		Flags = {},
		Visible = true,
		Running = true,

		_toggleKey = resolveOptionalKey(config.ToggleKey == nil and "RightShift" or config.ToggleKey),
		_width = width,
		_height = minHeight,
		_minHeight = minHeight,
		_x = math.floor(vw / 2 - width / 2),
		_y = math.floor(vh / 2 - minHeight / 2),
		_tabs = {},
		_currentTab = nil,
		_status = "Disconnected",
		_statusGood = false,
		_notifications = {},

		_pool = { Square = {}, Text = {}, Circle = {}, Line = {}, Image = {} },
		_used = { Square = 0, Text = 0, Circle = 0, Line = 0, Image = 0 },
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
		_focusedBox = nil,
		_maxFps = tonumber(config.MaxFps),
		_mini = config.Mini == true,
		_zBase = config.Mini and 100 or 0,
		_columns = config.Columns == 1 and 1 or 2,
		_closable = config.Closable == true,
		_hideTabs = config.HideTabs == true,
		_children = {},
		PerformanceEnabled = false,
		_perfPos = nil,
		_perfDrag = nil,
		_perfRect = nil,
		_fps = 0,
		_ping = nil,
		_statsNext = 0,
		_loopFrames = 0,
		_loopStart = now(),
		_keybinds = {},
		_saveables = {},
		_saveOrder = {},
		_pendingRestore = {},
		_dirty = false,
		_lastChange = 0,
		_autoSave = config.AutoSave ~= false,
		_listening = nil,
		_listenPrev = {},
		_logoData = nil,
		_logoSupported = true,
		_imageData = setmetatable({}, { __mode = "k" }),
		_props = setmetatable({}, { __mode = "k" }),
		_keyPrev = {},
		_backHeld = 0,
		_overlay = nil,
		_lastError = nil,
	}, Window)

	-- saved settings from the last run (applied to each element as it is created)
	self.Folder = cleanName(config.Folder or self.Title)
	if self.Folder == "" then
		self.Folder = "UiLibrary"
	end
	if self._mini then
		self._autoSave = false
		self._saved = {}
	else
		Storage.folder(self.Folder)
		Storage.folder(self.Folder .. "/configs")
		self._saved = Json.decode(Storage.read(self.Folder .. "/settings.json") or "") or {}
		if type(self._saved) ~= "table" then
			self._saved = {}
		end
	end

	if config.Logo then
		loadImage(config.Logo, function(data)
			self._logoData = data
		end)
	end

	if config.UniversalTab ~= false and not self._mini then
		self:_buildUniversalTab(type(config.UniversalTab) == "table" and config.UniversalTab or {}, config)
	end

	Library._windows = Library._windows or {}
	table.insert(Library._windows, self)
	if not self._mini then
		env.__UiLibraryWindow = self
		_G.__UiLibraryWindow = self
		if type(shared) == "table" then
			shared.__UiLibraryWindow = self
		end
		Library.ActiveWindow = self
	end

	spawnTask(function()
		while self.Running do
			local ok, err = pcall(self._frame, self)
			if not ok and tostring(err) ~= self._lastError then
				self._lastError = tostring(err)
				log("render error:", err)
			end
			-- redraw every frame (no fixed delay); MaxFps caps it if you want to save CPU
			if self._maxFps then
				waitTask(1 / self._maxFps)
			else
				waitTask()
			end
		end
	end)

	return self
end

--// drawing pool -------------------------------------------------------------
-- after Destroy, drawing calls go to a throwaway table instead of creating new objects
local deadObject = setmetatable({}, { __newindex = function() end, __index = function()
	return function() end
end })

-- Every Drawing property write is remembered per object and skipped when the value
-- hasn't changed. Writes are the expensive part in Matcha, and an idle menu changes
-- almost nothing between frames, so this keeps the UI from slowing other loops (ESP).
function Window:_get(kind)
	if not self.Running then
		return deadObject, {}
	end
	local used = self._used[kind] + 1
	self._used[kind] = used
	local object = self._pool[kind][used]
	if not object then
		object = Drawing.new(kind)
		self._pool[kind][used] = object
		self._props[object] = {}
	end
	local c = self._props[object]
	if c.Visible ~= true then
		c.Visible = true
		object.Visible = true
	end
	return object, c
end

local function setProp(o, c, key, value)
	if c[key] ~= value then
		c[key] = value
		o[key] = value
	end
end

local function setVec(o, c, key, x, y)
	local kx, ky = key .. "X", key .. "Y"
	if c[kx] ~= x or c[ky] ~= y then
		c[kx], c[ky] = x, y
		o[key] = Vector2.new(x, y)
	end
end

function Window:_hideUnused()
	for kind, list in pairs(self._pool) do
		for i = self._used[kind] + 1, #list do
			local o = list[i]
			local c = self._props[o]
			if not c or c.Visible ~= false then
				if c then
					c.Visible = false
				end
				o.Visible = false
			end
		end
	end
end

function Window:_rect(x, y, w, h, color, z, corner, alpha)
	if w <= 0 or h <= 0 then
		return
	end
	local o, c = self:_get("Square")
	setVec(o, c, "Position", math.floor(x), math.floor(y))
	setVec(o, c, "Size", math.floor(w), math.floor(h))
	setProp(o, c, "Color", color)
	setProp(o, c, "Filled", true)
	setProp(o, c, "Thickness", 1)
	setProp(o, c, "Transparency", alpha or 1)
	setProp(o, c, "ZIndex", (z or 1) + self._zBase)
	if self._cornerOk and c.Corner ~= (corner or 0) then
		local ok = pcall(function()
			o.Corner = corner or 0
		end)
		if ok then
			c.Corner = corner or 0
		else
			self._cornerOk = false
		end
	end
end

-- align: "left" (default), "center" or "right" relative to x
function Window:_text(str, x, y, color, size, z, align, alpha, outline)
	str = tostring(str or "")
	if str == "" then
		return
	end
	size = size or 13
	local o, c = self:_get("Text")
	if align == "center" then
		x = x - textWidth(str, size) / 2
	elseif align == "right" then
		x = x - textWidth(str, size)
	end
	setProp(o, c, "Text", str)
	setProp(o, c, "Size", size)
	setProp(o, c, "Font", FONT)
	setProp(o, c, "Center", false)
	setProp(o, c, "Outline", outline == true)
	setProp(o, c, "Color", color)
	setProp(o, c, "Transparency", alpha or 1)
	setProp(o, c, "ZIndex", (z or 5) + self._zBase)
	setVec(o, c, "Position", math.floor(x + 0.5), math.floor(y + 0.5))
end

function Window:_line(x1, y1, x2, y2, color, thickness, z, alpha)
	local o, c = self:_get("Line")
	setVec(o, c, "From", x1, y1)
	setVec(o, c, "To", x2, y2)
	setProp(o, c, "Color", color)
	setProp(o, c, "Thickness", thickness or 1)
	setProp(o, c, "Transparency", alpha or 1)
	setProp(o, c, "ZIndex", (z or 5) + self._zBase)
end

function Window:_image(data, x, y, w, h, z, rounding)
	local o, c = self:_get("Image")
	if c.Data ~= data then
		o.Data = data
		c.Data = data
	end
	setVec(o, c, "Position", math.floor(x), math.floor(y))
	setVec(o, c, "Size", w, h)
	setProp(o, c, "Transparency", 1)
	setProp(o, c, "ZIndex", (z or 5) + self._zBase)
	if c.Rounding ~= (rounding or 0) then
		c.Rounding = rounding or 0
		pcall(function()
			o.Rounding = rounding or 0
		end)
	end
end

function Window:_circle(x, y, radius, color, z, alpha)
	local o, c = self:_get("Circle")
	setVec(o, c, "Position", x, y)
	setProp(o, c, "Radius", radius)
	setProp(o, c, "Color", color)
	setProp(o, c, "Filled", true)
	setProp(o, c, "Thickness", 1)
	setProp(o, c, "NumSides", 20)
	setProp(o, c, "Transparency", alpha or 1)
	setProp(o, c, "ZIndex", (z or 5) + self._zBase)
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
	if self._clicked and self:_coveredByHigherWindow() then
		self._clicked = false
	end

	local busy = Library._anyTyping()
	local keyDown = self._toggleKey and Input.keyDown(self._toggleKey) or false
	if keyDown and not self._prevKey and not busy then
		self:Toggle()
	end
	self._prevKey = keyDown

	if self._listening then
		self:_listen()
	elseif not self._focusedBox then
		self:_runKeybinds()
	end

	if self._focusedBox then
		-- a click anywhere except the focused box submits it (the click still goes through)
		local r = self._focusedBox._rect
		if self._clicked and (not r or not self:_over(r.x, r.y, r.w, r.h)) then
			self._focusedBox:_unfocus(true)
		else
			self:_type()
		end
	end

	if not down then
		self._dragging = nil
		self._activeSlider = nil
		self._activeScroll = nil
	end

	self:_updateStats(t)
	if self.Visible then
		self:_perfInput() -- the performance bar sits on top, so it gets clicks first
		self:_handleOverlayClick()
		self:_drawWindow()
		self:_drawOverlay()
	else
		self._openDropdown = nil
		self._overlay = nil
		self._perfDrag = nil
	end
	if not self.Running then
		return
	end
	self:_drawPerf()
	if self._onDraw then
		local ok, err = pcall(self._onDraw, self)
		if not ok and tostring(err) ~= self._lastDrawError then
			self._lastDrawError = tostring(err)
			log("draw hook error:", err)
		end
	end
	if not self.Running then
		return
	end
	self:_drawNotifications(t)

	-- restore saved values for elements created since last frame (after the script built them)
	if #self._pendingRestore > 0 then
		local pending = self._pendingRestore
		self._pendingRestore = {}
		for _, item in ipairs(pending) do
			local ok, err = pcall(item.element._restore, item.element, item.value)
			if not ok then
				log("couldn't restore", item.flag, err)
			end
		end
	end
	if self._autoloadPending and #self._pendingRestore == 0 then
		local name = self._autoloadPending
		self._autoloadPending = nil
		if self:LoadConfig(name) then
			self:Notify("Configs", "Autoloaded " .. name, 3)
		end
	end
	if self._dirty and self._autoSave and t - self._lastChange > 0.5 then
		self:SaveSettings()
	end
	if not self.Running then
		return
	end

	self:_hideUnused()
end

--// several windows ---------------------------------------------------------------
function Window:_coveredByHigherWindow()
	for _, other in ipairs(Library._windows or {}) do
		if other ~= self and other.Running and other.Visible and other._zBase > self._zBase
			and self:_over(other._x, other._y, other._width, other._height) then
			return true
		end
	end
	return false
end

function Library._anyTyping()
	for _, w in ipairs(Library._windows or {}) do
		if w.Running and (w._focusedBox or w._listening) then
			return true
		end
	end
	return false
end

--// keybinds -------------------------------------------------------------------
function Window:_startListening(keybind)
	if self._focusedBox then
		self._focusedBox:_unfocus(true)
	end
	self._listening = keybind
	self._openDropdown = nil
	-- keys already held right now don't count
	for code = 3, 254 do
		self._listenPrev[code] = Input.vk(code)
	end
end

function Window:_listen()
	local keybind = self._listening
	-- clicking anywhere except its key box cancels
	if self._clicked then
		local r = keybind._rect
		if not r or not self:_over(r.x, r.y, r.w, r.h) then
			self._listening = nil
			return
		end
	end
	for code = 3, 254 do
		local down = Input.vk(code)
		local was = self._listenPrev[code]
		self._listenPrev[code] = down
		if down and not was then
			self._listening = nil
			if code == 0x1B then
				return -- Escape: keep the old key
			elseif code == 0x08 or code == 0x2E then
				if not keybind.Menu then -- the menu key can't be cleared, or the UI couldn't be reopened
					keybind:Set(nil) -- Backspace / Delete: clear
				end
			else
				keybind:Set(code)
			end
			-- don't fire the new bind for the press that set it
			keybind._prev = true
			if keybind.Menu then
				self._prevKey = true
			end
			return
		end
	end
end

function Window:_runKeybinds()
	for _, keybind in ipairs(self._keybinds) do
		if keybind.Key and not keybind.Menu then
			local down = Input.keyDown(keybind.Key)
			local was = keybind._prev
			keybind._prev = down
			if down ~= was then
				keybind:_fire(down)
			end
		end
	end
end

function Window:SetToggleKey(key)
	self._toggleKey = resolveOptionalKey(key)
	self._prevKey = true
end

--// typing into the focused textbox -------------------------------------------
function Window:_pressed(code)
	local down = Input.vk(code)
	local was = self._keyPrev[code]
	self._keyPrev[code] = down
	return down and not was
end

function Window:_type()
	local box = self._focusedBox
	if not box then
		return
	end

	if self:_pressed(VK_ENTER) then
		box:_unfocus(true)
		return
	end
	if self:_pressed(VK_ESCAPE) then
		box:_unfocus(false)
		return
	end

	-- backspace: once on press, then repeats while held
	local back = Input.vk(VK_BACK)
	if back then
		if self._backHeld == 0 then
			box:_backspace()
			self._backHeld = 0.0001
		else
			self._backHeld = self._backHeld + self._dt
			if self._backHeld > 0.4 then
				box:_backspace()
				self._backHeld = 0.4 - 0.035
			end
		end
	else
		self._backHeld = 0
	end

	local shift = Input.shift()
	for code, chars in pairs(TypingKeys) do
		if self:_pressed(code) then
			box:_insert(shift and chars[2] or chars[1])
		end
	end
end

--// performance bar ------------------------------------------------------------
-- "Title | 240 fps | 45 ms": bottom-middle by default, draggable while the UI is open,
-- visible even when the UI is hidden.
local Stats
pcall(function()
	Stats = game:GetService("Stats")
end)

-- Matcha prints errors even inside pcall, so these lookups avoid erroring:
-- FindFirstChild instead of indexing, type checks before calling.
local function child(parent, name)
	if parent == nil then
		return nil
	end
	local ok, found = pcall(function()
		return parent:FindFirstChild(name)
	end)
	return ok and found or nil
end

local function itemValue(item)
	if item == nil then
		return nil
	end
	local ok, v = pcall(function()
		return item.Value
	end)
	if ok and type(v) == "number" then
		return v
	end
	ok, v = pcall(function()
		return item:GetValue()
	end)
	if ok and type(v) == "number" then
		return v
	end
	ok, v = pcall(function()
		return tonumber(tostring(item:GetValueString()):match("[%d%.]+"))
	end)
	return ok and v or nil
end

local function nativePing()
	local fn = rawget(_G, "GetPingValue")
	if type(fn) ~= "function" and type(getgenv) == "function" then
		local env = getgenv()
		fn = type(env) == "table" and rawget(env, "GetPingValue") or nil
	end
	if type(fn) ~= "function" then
		pcall(function()
			fn = GetPingValue
		end)
	end
	if type(fn) == "function" then
		local ok, v = pcall(fn)
		return ok and v or nil
	end
	return nil
end

-- tried in order until one gives a usable number; the working one is remembered
local PingMethods = {
	{ "native GetPingValue", nativePing },
	{ "Data Ping", function()
		return itemValue(child(child(child(Stats, "Network"), "ServerStatsItem"), "Data Ping"))
	end },
	{ "PerformanceStats.Ping", function()
		return itemValue(child(child(Stats, "PerformanceStats"), "Ping"))
	end },
	{ "GetNetworkPing", function()
		local ok, v = pcall(function()
			return Players.LocalPlayer:GetNetworkPing() * 1000
		end)
		return ok and v or nil
	end },
}

local function validPing(v)
	return type(v) == "number" and v == v and v > 0 and v < 10000
end

local pingMethod = nil -- index of the method that worked last
local pingRetryAt = 0

local function readPing()
	if pingMethod then
		local v = PingMethods[pingMethod][2]()
		if validPing(v) then
			return v
		end
		pingMethod = nil
	end
	if now() < pingRetryAt then
		return nil
	end
	for i, method in ipairs(PingMethods) do
		local v = method[2]()
		if validPing(v) then
			pingMethod = i
			Library.PingMethod = method[1]
			return v
		end
	end
	Library.PingMethod = "none"
	pingRetryAt = now() + 10 -- nothing works right now; don't try every update
	return nil
end

local fpsMethodWorks = true
local function readFps()
	if not fpsMethodWorks then
		return nil
	end
	if type(getfps) == "function" then
		local ok, v = pcall(getfps)
		if ok and type(v) == "number" and v > 0 then
			return v
		end
	end
	fpsMethodWorks = false -- fall back to the UI's own frame rate from now on
	return nil
end

function Window:_updateStats(t)
	self._loopFrames = self._loopFrames + 1
	if t < self._statsNext then
		return
	end
	local elapsed = t - self._loopStart
	local loopFps = elapsed > 0 and self._loopFrames / elapsed or 0
	self._loopFrames, self._loopStart = 0, t
	self._statsNext = t + 0.5
	if not self.PerformanceEnabled then
		return
	end
	-- the game's FPS when the executor can read it, otherwise how fast the UI redraws
	self._fps = readFps() or loopFps
	self._ping = readPing()
end

function Window:_perfParts()
	local ping = self._ping and (math.floor(self._ping + 0.5) .. " ms") or "-- ms"
	return { self.Title, string.format("%d fps", math.floor(self._fps + 0.5)), ping }
end

function Window:_perfSize()
	local parts = self:_perfParts()
	local w = 10 + 18 + 6
	for i, part in ipairs(parts) do
		w = w + textWidth(part, SMALL) * FIT_MARGIN
		if i < #parts then
			w = w + 16 -- " | "
		end
	end
	return math.floor(w + 10), 26
end

function Window:_perfPosition(w, h)
	local vw, vh = viewportSize()
	local x, y
	if self._perfPos then
		x, y = self._perfPos.X, self._perfPos.Y
	else
		x, y = vw / 2 - w / 2, vh - h - 24
	end
	return clamp(x, 0, math.max(0, vw - w)), clamp(y, 0, math.max(0, vh - h))
end

function Window:_perfInput()
	if not self.PerformanceEnabled then
		self._perfDrag = nil
		return
	end
	local w, h = self:_perfSize()
	local x, y = self:_perfPosition(w, h)
	if self:_clickIn(x, y, w, h) then
		self._perfDrag = Vector2.new(self._mouseX - x, self._mouseY - y)
	end
	if self._perfDrag then
		if self._down then
			self._perfPos = Vector2.new(self._mouseX - self._perfDrag.X, self._mouseY - self._perfDrag.Y)
		else
			self._perfDrag = nil
			local px, py = self:_perfPosition(w, h)
			self.Flags.UI_PerfPos = { math.floor(px), math.floor(py) }
			self:_markDirty()
		end
	end
end

function Window:_drawPerf()
	if not self.PerformanceEnabled then
		return
	end
	local th = self.Theme
	local w, h = self:_perfSize()
	local x, y = self:_perfPosition(w, h)
	local dragging = self._perfDrag ~= nil
	self:_box(x, y, w, h, th.Background, dragging and th.Accent or th.Border, 55, 5)

	-- logo
	local drewImage = false
	if self._logoData and self._logoSupported then
		drewImage = pcall(self._image, self, self._logoData, x + 9, y + 4, 18, 18, 57, 3)
	end
	if not drewImage then
		local a = th.Accent
		local lx, ly = x + 10, y + 8
		self:_line(lx, ly, lx + 6, ly + 9, a, 2.5, 57)
		self:_line(lx + 6, ly + 9, lx + 13, ly, a, 2.5, 57)
	end

	local tx = x + 10 + 18 + 6
	local ty = y + (h - SMALL) / 2 - 1
	local parts = self:_perfParts()
	for i, part in ipairs(parts) do
		self:_text(part, tx, ty, i == 1 and th.Text or th.TextDim, SMALL, 57)
		tx = tx + textWidth(part, SMALL) * FIT_MARGIN
		if i < #parts then
			self:_text("|", tx + 5, ty, th.TextMuted, SMALL, 57)
			tx = tx + 16
		end
	end
end

--// window body --------------------------------------------------------------
function Window:_layoutColumn(tab, side, colW)
	local total = 0
	local list = {}
	for _, section in ipairs(tab._sections) do
		if side == nil or section.Side == side then
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

local function hasIcon(icon)
	return icon ~= nil and icon ~= "" and not tostring(icon):find("rbxasset")
end

function Window:_tabWidths()
	local widths = {}
	for i, t in ipairs(self._tabs) do
		local iconW = hasIcon(t.Icon) and textWidth(t.Icon, TEXT) or 0
		if t == self._currentTab or iconW == 0 then
			-- selected tab (or tab without icon): icon + name in a pill
			local w = 26 + textWidth(t.Name, TEXT)
			if iconW > 0 then
				w = w + iconW + 8
			end
			widths[i] = w
		else
			widths[i] = math.max(26, iconW + 16)
		end
	end
	return widths
end

function Window:_drawLogo(x, y)
	-- small accent chevron mark
	local a = self.Theme.Accent
	self:_line(x, y, x + 7, y + 11, a, 3, 5)
	self:_line(x + 7, y + 11, x + 15, y, a, 3, 5)
	self:_line(x + 3, y, x + 7, y + 6, a, 2, 5)
	self:_line(x + 7, y + 6, x + 11, y, a, 2, 5)
end

function Window:_drawWindow()
	local th = self.Theme
	local W = self._width
	local oneColumn = self._columns == 1
	local colW = oneColumn and (W - EDGE * 2) or math.floor((W - EDGE * 2 - PAD) / 2)
	local tab = self._currentTab

	local left, leftH, right, rightH = {}, 0, {}, 0
	if tab then
		left, leftH = self:_layoutColumn(tab, oneColumn and nil or "Left", colW)
		if not oneColumn then
			right, rightH = self:_layoutColumn(tab, "Right", colW)
		end
	end
	-- fixed height like the reference; grows only if a tab needs more room
	local H = math.max(self._minHeight, TOPBAR + EDGE + 1 + math.max(leftH, rightH) + EDGE + FOOTER)
	self._height = H

	-- dragging by the top bar
	if self._dragging then
		self._x = self._mouseX - self._dragging.X
		self._y = self._mouseY - self._dragging.Y
	end
	local x, y = self._x, self._y

	-- frame
	self:_box(x, y, W, H, th.Background, th.Border, 1, 4)
	self:_rect(x, y, W, TOPBAR, th.Topbar, 2, 4)
	self:_rect(x, y + TOPBAR - 4, W, 4, th.Topbar, 2)

	-- brand: logo, title, subtitle on one line
	local drewImage = false
	if self._logoData and self._logoSupported then
		local ok = pcall(self._image, self, self._logoData, x + 9, y + 9, 20, 20, 5, 4)
		if ok then
			drewImage = true
		else
			self._logoSupported = false
			log("this executor can't draw images, using the default logo")
		end
	end
	if not drewImage then
		self:_drawLogo(x + 12, y + 12)
	end
	local titleX = x + 34
	local title = fitText(self.Title, self._hideTabs and (W - 80) or W * 0.3, TEXT)
	self:_text(title, titleX, y + 12, th.Text, TEXT, 5)
	if self.Subtitle ~= "" then
		local subX = titleX + textWidth(title, TEXT) + 10
		self:_text(fitText(self.Subtitle, W * 0.2, 11), subX, y + 13, th.TextDim, 11, 5)
	end

	-- close button (mini windows)
	if self._closable then
		local cs = 20
		local cx, cy = x + W - cs - 9, y + (TOPBAR - cs) / 2
		local hover = self:_over(cx, cy, cs, cs)
		if hover then
			self:_rect(cx, cy, cs, cs, th.Section, 4, 4)
		end
		local col = hover and th.Accent or th.TextDim
		self:_line(cx + 6, cy + 6, cx + cs - 6, cy + cs - 6, col, 1.5, 5)
		self:_line(cx + cs - 6, cy + 6, cx + 6, cy + cs - 6, col, 1.5, 5)
		if self:_clickIn(cx, cy, cs, cs) then
			self:Destroy()
			return
		end
	end

	-- tabs: right-aligned; the selected one is a dark pill with icon + name
	local widths = self._hideTabs and {} or self:_tabWidths()
	local total = 0
	for _, w in ipairs(widths) do
		total = total + w + 4
	end
	local tx = x + W - 12 - total + 4
	local pillY, pillH = y + 5, TOPBAR - 10
	for i, t in ipairs(self._hideTabs and {} or self._tabs) do
		local w = widths[i]
		local selected = t == self._currentTab
		local hover = self:_over(tx, pillY, w, pillH)
		if selected then
			self:_rect(tx, pillY, w, pillH, th.TabActive, 4, 5)
		elseif hover then
			self:_rect(tx, pillY, w, pillH, th.Section, 4, 5)
		end
		local cx = tx + 12
		local textY = pillY + (pillH - TEXT) / 2 - 1
		if hasIcon(t.Icon) then
			if selected then
				self:_text(t.Icon, cx, textY, th.Accent, TEXT, 5)
				cx = cx + textWidth(t.Icon, TEXT) + 8
			else
				self:_text(t.Icon, tx + w / 2, textY, hover and th.Text or th.TextDim, TEXT, 5, "center")
			end
		end
		if selected or not hasIcon(t.Icon) then
			self:_text(t.Name, cx, textY, (selected or hover) and th.Text or th.TextDim, TEXT, 5)
		end
		if self:_clickIn(tx, pillY, w, pillH) then
			self:SelectTab(t)
		end
		tx = tx + w + 4
	end

	-- start dragging when the top bar (outside the tabs) is clicked
	if self:_clickIn(x, y, W, TOPBAR) then
		self._dragging = Vector2.new(self._mouseX - x, self._mouseY - y)
	end

	-- columns
	local top = y + TOPBAR + EDGE + 1
	local function drawColumn(list, cx)
		local cy = top
		for _, entry in ipairs(list) do
			entry.section:_draw(self, cx, cy, colW, entry.h)
			cy = cy + entry.h + PAD
		end
	end
	drawColumn(left, x + EDGE)
	if not oneColumn then
		drawColumn(right, x + W - EDGE - colW)
	end

	-- footer
	local fy = y + H - FOOTER
	self:_rect(x, fy, W, FOOTER, th.Footer, 2, 4)
	self:_rect(x, fy, W, 4, th.Footer, 2)
	self:_circle(x + 12, fy + FOOTER / 2, 3, self._statusGood and th.Good or th.Bad, 5)
	self:_text(fitText(self._status, W - 34, SMALL), x + 21, fy + (FOOTER - SMALL) / 2 - 1, th.Text, SMALL, 5)

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
		self:_text(fitText(option, w - 20, SMALL), x + 10, iy + (itemH - SMALL) / 2 - 1, selected and th.Accent or th.Text, SMALL, 43)
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
	local universal = self._universalTab
	if universal and not config._universal then
		-- keep the built-in UI tab last
		table.insert(self._tabs, #self._tabs, tab)
	else
		self._tabs[#self._tabs + 1] = tab
	end
	if not self._currentTab or (self._currentTab == universal and not config._universal) then
		self._currentTab = tab
	end
	return tab
end

function Window:SelectTab(tab)
	if tab and tab ~= self._currentTab then
		if self._focusedBox then
			self._focusedBox:_unfocus(true)
		end
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
		if self._focusedBox then
			self._focusedBox:_unfocus(true)
		end
		self._openDropdown = nil
		self._overlay = nil
		self._dragging = nil
		self._activeSlider = nil
	end
end

--// saving ---------------------------------------------------------------------
-- every element with a Flag (and Save ~= false) is saved and restored
function Window:_register(flag, element)
	if not flag then
		return
	end
	if not self._saveables[flag] then
		self._saveOrder[#self._saveOrder + 1] = flag
	end
	self._saveables[flag] = element
	local saved = self._saved[flag]
	if saved ~= nil then
		self._pendingRestore[#self._pendingRestore + 1] = { flag = flag, element = element, value = saved }
	end
end

function Window:_markDirty()
	self._dirty = true
	self._lastChange = now()
end

function Window:_snapshot(forConfig)
	local data = {}
	for _, flag in ipairs(self._saveOrder) do
		local value = self.Flags[flag]
		local element = self._saveables[flag]
		if value ~= nil and not (forConfig and element._noConfig) then
			data[flag] = value
		end
	end
	return data
end

function Window:SaveSettings()
	self._dirty = false
	-- keep saved values of elements that haven't been created (yet) this run
	local data = {}
	for k, v in pairs(self._saved) do
		data[k] = v
	end
	for k, v in pairs(self:_snapshot()) do
		data[k] = v
	end
	self._saved = data
	Storage.write(self.Folder .. "/settings.json", Json.encode(data))
end

function Window:_applyValues(data)
	for flag, value in pairs(data) do
		local element = self._saveables[flag]
		if element then
			local ok, err = pcall(element._restore, element, value)
			if not ok then
				log("couldn't load", flag, err)
			end
		else
			-- element not created yet (e.g. autoload runs while the script is still
			-- building the UI): it picks this value up when it's created
			self._saved[flag] = value
		end
	end
end

--// configs ----------------------------------------------------------------------
function Window:_configPath(name)
	return self.Folder .. "/configs/" .. name .. ".json"
end

function Window:ListConfigs()
	local list = Json.decode(Storage.read(self.Folder .. "/configs/index.json") or "") or {}
	local out = {}
	for _, name in ipairs(list) do
		if type(name) == "string" and Storage.read(self:_configPath(name)) then
			out[#out + 1] = name
		end
	end
	table.sort(out, function(a, b)
		return a:lower() < b:lower()
	end)
	return out
end

function Window:_writeIndex(list)
	Storage.write(self.Folder .. "/configs/index.json", Json.encode(list))
end

function Window:SaveConfig(name)
	name = cleanName(name)
	if name == "" then
		return false, "Enter a config name"
	end
	Storage.write(self:_configPath(name), Json.encode(self:_snapshot(true)))
	local list = self:ListConfigs()
	local found = false
	for _, n in ipairs(list) do
		if n == name then
			found = true
		end
	end
	if not found then
		list[#list + 1] = name
	end
	self:_writeIndex(list)
	return true
end

function Window:LoadConfig(name)
	name = cleanName(name)
	local data = Json.decode(Storage.read(self:_configPath(name)) or "")
	if type(data) ~= "table" then
		return false, "Config not found"
	end
	self:_applyValues(data)
	return true
end

function Window:DeleteConfig(name)
	name = cleanName(name)
	Storage.delete(self:_configPath(name))
	local list = {}
	for _, n in ipairs(self:ListConfigs()) do
		if n ~= name then
			list[#list + 1] = n
		end
	end
	self:_writeIndex(list)
	return true
end

function Window:RenameConfig(old, new)
	old, new = cleanName(old), cleanName(new)
	if new == "" then
		return false, "Enter a new name"
	end
	local content = Storage.read(self:_configPath(old))
	if not content then
		return false, "Config not found"
	end
	if old == new then
		return true
	end
	Storage.write(self:_configPath(new), content)
	Storage.delete(self:_configPath(old))
	local list = {}
	for _, n in ipairs(self:ListConfigs()) do
		if n ~= old and n ~= new then
			list[#list + 1] = n
		end
	end
	list[#list + 1] = new
	self:_writeIndex(list)
	return true
end

-- cap = number, or nil for unlimited
function Window:SetFpsCap(cap)
	cap = tonumber(cap)
	if cap and cap <= 0 then
		cap = nil
	end
	self._maxFps = cap
	if type(setfpscap) == "function" then
		pcall(setfpscap, cap or 0) -- 0 = uncapped for most executors
	end
end

function Window:SetFont(name)
	FONT = FontIds[name] or (type(name) == "number" and name) or FONT
end

function Window:SetTheme(theme)
	local new = buildTheme(theme)
	for k in pairs(self.Theme) do
		self.Theme[k] = nil
	end
	for k, v in pairs(new) do
		self.Theme[k] = v
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
	if self.NotificationsEnabled == false then
		return
	end
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
	if not self.Running then
		return
	end
	for _, child in ipairs(self._children) do
		pcall(child.Destroy, child)
	end
	if Library._windows then
		for i = #Library._windows, 1, -1 do
			if Library._windows[i] == self then
				table.remove(Library._windows, i)
			end
		end
	end
	runCallback(self._onClose)
	if self._dirty and self._autoSave then
		pcall(self.SaveSettings, self)
	end
	self.Running = false
	self.Visible = false
	self._notifications = {}
	self._keybinds = {}
	self._focusedBox = nil
	self._listening = nil
	self._openDropdown = nil
	for _, list in pairs(self._pool) do
		for _, object in ipairs(list) do
			pcall(function()
				object.Visible = false
			end)
			pcall(function()
				object:Remove()
			end)
		end
	end
	self._pool = { Square = {}, Text = {}, Circle = {}, Line = {}, Image = {} }
	self._props = setmetatable({}, { __mode = "k" })
	local env = (type(getgenv) == "function" and getgenv()) or _G
	for _, holder in ipairs({ env, _G, type(shared) == "table" and shared or {} }) do
		if rawget(holder, "__UiLibraryWindow") == self then
			rawset(holder, "__UiLibraryWindow", nil)
		end
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
	local h = SECTION_HEADER + 8
	local inner = colW - INSET * 2
	for _, el in ipairs(self._elements) do
		if el.Visible ~= false then
			h = h + el:_height(inner) + ELEMENT_GAP
		end
	end
	return h + 2
end

function Section:_draw(win, x, y, w, h)
	local th = win.Theme
	-- body, then a lighter header strip across the top
	win:_rect(x, y, w, h, th.Section, 6, 4)
	win:_rect(x, y, w, SECTION_HEADER, th.SectionHeader or th.Element, 7, 4)
	win:_rect(x, y + SECTION_HEADER - 4, w, 4, th.SectionHeader or th.Element, 7)

	local ty = y + (SECTION_HEADER - TEXT) / 2
	win:_text(fitText(self.Name, w - INSET * 2, TEXT), x + INSET, ty, th.Text, TEXT, 9)

	local ey = y + SECTION_HEADER + 8
	local inner = w - INSET * 2
	for _, el in ipairs(self._elements) do
		if el.Visible ~= false then
			local eh = el:_height(inner)
			el:_draw(win, x + INSET, ey, inner, eh)
			ey = ey + eh + ELEMENT_GAP
		end
	end
end

local function setVisible(element, visible)
	element.Visible = visible ~= false
end

function Section:_add(element)
	element.Section = self
	element.Window = self.Window
	element.SetVisible = setVisible
	self._elements[#self._elements + 1] = element
	return element
end

function Section:_register(element, config)
	if element.Flag and config.Save ~= false then
		-- Config = false: saved between runs, but not part of configs
		element._noConfig = config.Config == false
		self.Window:_register(element.Flag, element)
	end
end

function Section:_setFlag(flag, value)
	if flag then
		self.Window.Flags[flag] = value
		self.Window:_markDirty()
	end
end

--// label --------------------------------------------------------------------
local Label = {}
Label.__index = Label

function Section:AddLabel(text)
	return self:_add(setmetatable({ Text = tostring(text or "") }, Label))
end

function Label:_height(w)
	return #wrapText(self.Text, w, SMALL) * 16
end

function Label:_draw(win, x, y, w)
	for i, line in ipairs(wrapText(self.Text, w, SMALL)) do
		win:_text(line, x, y + (i - 1) * 16, win.Theme.TextDim, SMALL, 12)
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
	local border = self._flash > 0 and th.Accent or fill
	win:_box(x, y, w, h, fill, border, 10, 4)
	win:_text(fitText(self.Text, w - 16, TEXT), x + w / 2, y + (h - TEXT) / 2 - 1, th.Text, TEXT, 12, "center")
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
	self:_setFlag(toggle.Flag, toggle.Value)
	self:_register(toggle, config)
	if config.Keybind ~= nil then
		-- Keybind = "F" (or "None" to start unbound): pressing it flips the toggle
		local mode = config.KeybindMode or "Toggle"
		toggle.Keybind = newKeybind(self.Window, {
			Default = config.Keybind,
			Mode = "Hold",
			-- saved as <Flag>Key so a rebound key comes back next time
			Flag = config.KeybindFlag or (toggle.Flag and toggle.Flag .. "Key"),
			Save = config.Save,
			Callback = function(down)
				if mode == "Hold" then
					toggle:Set(down)
				elseif down then
					toggle:Set(not toggle.Value)
				end
			end,
		})
	end
	return toggle
end

function Toggle:_height()
	return 18
end

function Toggle:_draw(win, x, y, w, h)
	local th = win.Theme
	local size = 12
	local keyW = 0
	if self.Keybind then
		-- key box sits left of the checkbox and is drawn first so it gets its own clicks
		keyW = self.Keybind:_drawBox(win, x + w - size - 6, y, h) + 6
	end

	local hover = win:_over(x, y, w, h)
	if win:_clickIn(x, y, w, h) then
		self:Set(not self.Value)
	end

	local color = self.Value and th.Text or (hover and th.Text or th.TextDim)
	win:_text(fitText(self.Text, w - 24 - keyW, TEXT), x, y + (h - TEXT) / 2 - 1, color, TEXT, 12)

	local bx, by = x + w - size, y + (h - size) / 2
	if self.Value then
		-- glow, accent border, filled box, check mark
		win:_rect(bx - 2, by - 2, size + 4, size + 4, th.AccentSoft, 10, 5, 0.35)
		win:_box(bx, by, size, size, th.Accent, th.Accent, 11, 3)
		win:_rect(bx + 2, by + 2, size - 4, size - 4, th.AccentSoft, 13, 2)
		local mark = th.AccentText or th.Text
		win:_line(bx + 3, by + 6, bx + 5, by + 8.5, mark, 1.5, 14)
		win:_line(bx + 5, by + 8.5, bx + 9, by + 3.5, mark, 1.5, 14)
	else
		win:_box(bx, by, size, size, hover and th.ElementHover or th.Element, th.Border, 11, 3)
	end
end

function Toggle:Set(value)
	self.Value = value == true
	self.Section:_setFlag(self.Flag, self.Value)
	runCallback(self.Callback, self.Value)
end

function Toggle:Get()
	return self.Value
end

function Toggle:_restore(value)
	if type(value) == "boolean" and value ~= self.Value then
		self:Set(value)
	end
end

-- give keyboard focus to a textbox or a slider's value
local function focusTarget(win, target)
	if win._focusedBox and win._focusedBox ~= target then
		win._focusedBox:_unfocus(true)
	end
	win._focusedBox = target
	win._openDropdown = nil
	-- ignore keys that are already held when focusing
	for code in pairs(TypingKeys) do
		win._keyPrev[code] = Input.vk(code)
	end
	win._keyPrev[VK_ENTER] = Input.vk(VK_ENTER)
	win._keyPrev[VK_ESCAPE] = Input.vk(VK_ESCAPE)
	win._backHeld = Input.vk(VK_BACK) and 1 or 0
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
		_typed = "",
		Suffix = config.Suffix or "",
		Flag = config.Flag,
		Callback = config.Callback,
	}, Slider))
	slider.Value = slider:_round(tonumber(config.Default) or min)
	self:_setFlag(slider.Flag, slider.Value)
	self:_register(slider, config)
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
	return 32
end

function Slider:_draw(win, x, y, w)
	local th = win.Theme
	local barY, barH = y + LABEL_GAP, 13

	if win:_clickIn(x, barY - 4, w, barH + 8) then
		win._activeSlider = self
		self._dragX = nil
	end
	if win._activeSlider == self and win._down and win._mouseX ~= self._dragX then
		self._dragX = win._mouseX
		local pct = clamp((win._mouseX - x) / w, 0, 1)
		self:Set(self.Min + (self.Max - self.Min) * pct)
	end

	-- the value in the top-right: click it to type a number
	local editing = win._focusedBox == self
	local valueText = editing and self._typed or self:_format()
	local vw = math.max(textWidth(valueText, TEXT) * FIT_MARGIN, editing and 36 or 0) + 10
	local vx, vy, vh = x + w - vw + 4, y - 3, TEXT + 6
	self._rect = { x = vx, y = vy, w = vw, h = vh }
	local overValue = win:_over(vx, vy, vw, vh)
	if win:_clickIn(vx, vy, vw, vh) and not editing then
		self:_startEdit()
		editing = true
		valueText = self._typed
	end
	if editing or overValue then
		win:_box(vx, vy, vw, vh, th.Element, editing and th.Accent or th.Border, 10, 3)
	end
	win:_text(fitText(self.Text, w - vw - 6, TEXT), x, y, th.Text, TEXT, 12)
	win:_text(valueText, x + w, y, editing and th.Accent or th.Text, TEXT, 12, "right")
	if editing and (os.clock() % 1) < 0.55 then
		win:_rect(x + w + 1, vy + 3, 1, vh - 6, th.Accent, 13)
	end

	local range = self.Max - self.Min
	local pct = range > 0 and (self.Value - self.Min) / range or 0
	local hover = win:_over(x, barY - 4, w, barH + 8) or win._activeSlider == self
	local fillW = math.floor(w * pct)
	win:_rect(x, barY, w, barH, hover and th.ElementHover or th.Element, 10, 3)
	if fillW > 0 then
		win:_rect(x, barY, math.max(fillW, 4), barH, th.Accent, 11, 3)
	end

	-- value inside the bar: just past the fill, or inside it near the end when full
	local label = valueText
	local lw = textWidth(label, 11)
	local lx = x + fillW + 8
	if lx + lw > x + w - 4 then
		lx = x + fillW - lw - 8
	end
	win:_text(label, lx, barY + (barH - 11) / 2 - 1, th.Text, 11, 13)
end

-- typing a value (Enter or clicking away applies it, Escape cancels)
function Slider:_startEdit()
	self._typed = ""
	focusTarget(self.Window, self)
end

function Slider:_insert(char)
	if char:match("[%d%.%-]") and #self._typed < 12 then
		self._typed = self._typed .. char
	end
end

function Slider:_backspace()
	self._typed = self._typed:sub(1, -2)
end

function Slider:_unfocus(submit)
	local win = self.Window
	if win._focusedBox ~= self then
		return
	end
	win._focusedBox = nil
	local n = tonumber(self._typed)
	if submit and n then
		-- out of range snaps to the nearest end
		self:Set(clamp(n, self.Min, self.Max))
	end
	self._typed = ""
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

function Slider:_restore(value)
	if type(value) == "number" then
		self:Set(value)
	end
end

--// keybind ------------------------------------------------------------------
-- Modes: "Press" (Callback() on each press), "Toggle" (Callback(on) flips each press),
-- "Hold" (Callback(true) on press, Callback(false) on release).
-- Menu = true makes it the window's show / hide key.
local Keybind = {}
Keybind.__index = Keybind

function newKeybind(window, config) -- assigns the forward-declared local
	local keybind = setmetatable({
		Window = window,
		Key = resolveOptionalKey(config.Default),
		Mode = config.Mode or "Press",
		Menu = config.Menu == true,
		State = false,
		Callback = config.Callback,
		ChangedCallback = config.ChangedCallback,
		Flag = config.Flag,
		_prev = true,
	}, Keybind)
	window._keybinds[#window._keybinds + 1] = keybind
	if keybind.Flag then
		window.Flags[keybind.Flag] = keybind:Get() or "None"
		if config.Save ~= false then
			keybind._noConfig = config.Config == false
			window:_register(keybind.Flag, keybind)
		end
	end
	if keybind.Menu then
		if keybind.Key then
			window._toggleKey = keybind.Key
		else
			keybind.Key = window._toggleKey
		end
	end
	return keybind
end

function Keybind:_fire(down)
	if self.Mode == "Hold" then
		self.State = down
		runCallback(self.Callback, down)
	elseif down then
		if self.Mode == "Toggle" then
			self.State = not self.State
			runCallback(self.Callback, self.State)
		else
			runCallback(self.Callback)
		end
	end
end

function Keybind:_label()
	if self.Window._listening == self then
		return "..."
	end
	return self.Key and self.Key.name or "None"
end

function Keybind:_boxWidth()
	return math.max(30, math.floor(textWidth(self:_label(), SMALL) * FIT_MARGIN) + 14)
end

-- draws the key box with its right edge at `right`; returns its width
function Keybind:_drawBox(win, right, y, h)
	local th = win.Theme
	local w = self:_boxWidth()
	local x = right - w
	self._rect = { x = x, y = y, w = w, h = h }
	local listening = win._listening == self
	if win:_clickIn(x, y, w, h) and not listening then
		win:_startListening(self)
		listening = true
	end
	local hover = win:_over(x, y, w, h)
	local fill = (hover or listening) and th.ElementHover or th.Element
	win:_box(x, y, w, h, fill, listening and th.Accent or th.Border, 10, 3)
	win:_text(self:_label(), x + w / 2, y + (h - SMALL) / 2 - 1, listening and th.Accent or th.TextDim, SMALL, 12, "center")
	return w
end

function Keybind:Set(key)
	if key ~= nil and type(key) ~= "table" then
		key = resolveOptionalKey(key)
	end
	self.Key = key
	self._prev = true
	if self.Menu then
		self.Window:SetToggleKey(key and key.vk or nil)
	end
	if self.Flag then
		self.Window.Flags[self.Flag] = self:Get() or "None"
		self.Window:_markDirty()
	end
	runCallback(self.ChangedCallback, self:Get())
end

function Keybind:Get()
	return self.Key and self.Key.name or nil
end

function Keybind:GetState()
	return self.State
end

function Keybind:_restore(value)
	if type(value) == "string" and value ~= (self:Get() or "None") then
		if self.Menu and value == "None" then
			return
		end
		self:Set(value)
	end
end

-- standalone keybind row
local KeybindRow = {}
KeybindRow.__index = KeybindRow

function Section:AddKeybind(config)
	config = config or {}
	local row = self:_add(setmetatable({ Text = config.Name or "Keybind" }, KeybindRow))
	row.Keybind = newKeybind(self.Window, config)
	-- expose Set / Get / GetState on the row
	row.Set = function(_, key)
		row.Keybind:Set(key)
	end
	row.Get = function()
		return row.Keybind:Get()
	end
	row.GetState = function()
		return row.Keybind.State
	end
	return row
end

function KeybindRow:_height()
	return 18
end

function KeybindRow:_draw(win, x, y, w, h)
	local th = win.Theme
	local boxW = self.Keybind:_drawBox(win, x + w, y, h)
	win:_text(fitText(self.Text, w - boxW - 8, TEXT), x, y + (h - TEXT) / 2 - 1, th.Text, TEXT, 12)
end

--// list ---------------------------------------------------------------------
-- rows of text; items = { { Text = "left", Right = "right", Value = anything }, ... }
local List = {}
List.__index = List

function Section:AddList(config)
	config = config or {}
	return self:_add(setmetatable({
		Rows = tonumber(config.Rows) or 6,
		Empty = config.Empty or "Nothing yet",
		OnClick = config.OnClick,
		Items = {},
	}, List))
end

local LIST_ROW = 18
local SCROLL_W = 5

function List:_height()
	return self.Rows * LIST_ROW + 4
end

function List:_maxScroll()
	return math.max(0, #self.Items - self.Rows)
end

function List:_draw(win, x, y, w, h)
	local th = win.Theme
	win:_rect(x, y, w, h, th.Element, 10, 4)
	if #self.Items == 0 then
		win:_text(fitText(self.Empty, w - 16, SMALL), x + 8, y + 5, th.TextMuted, SMALL, 12)
		return
	end
	local maxScroll = self:_maxScroll()
	self.Scroll = clamp(math.floor(self.Scroll or 0), 0, maxScroll)
	local scrollable = maxScroll > 0
	local rowW = scrollable and (w - SCROLL_W - 6) or w

	-- scrollbar: drag the thumb or click the track (Matcha has no mouse wheel)
	if scrollable then
		local tx, ty, th2 = x + w - SCROLL_W - 3, y + 3, h - 6
		local thumbH = math.max(14, math.floor(th2 * self.Rows / #self.Items))
		local thumbY = ty + math.floor((th2 - thumbH) * self.Scroll / maxScroll + 0.5)
		if win:_clickIn(tx - 3, ty, SCROLL_W + 6, th2) then
			win._activeScroll = self
			local onThumb = win._mouseY >= thumbY and win._mouseY <= thumbY + thumbH
			self._grab = onThumb and (win._mouseY - thumbY) or thumbH / 2
		end
		if win._activeScroll == self then
			if win._down then
				local pct = clamp((win._mouseY - self._grab - ty) / math.max(1, th2 - thumbH), 0, 1)
				self.Scroll = math.floor(pct * maxScroll + 0.5)
				thumbY = ty + math.floor((th2 - thumbH) * self.Scroll / maxScroll + 0.5)
			else
				win._activeScroll = nil
			end
		end
		win:_rect(tx, ty, SCROLL_W, th2, th.Section, 11, 2)
		local active = win._activeScroll == self or win:_over(tx - 3, ty, SCROLL_W + 6, th2)
		win:_rect(tx, thumbY, SCROLL_W, thumbH, active and th.Accent or th.TextMuted, 12, 2)
	end

	for i = 1, math.min(self.Rows, #self.Items - self.Scroll) do
		local item = self.Items[i + self.Scroll]
		local ry = y + 2 + (i - 1) * LIST_ROW
		local hover = win:_over(x, ry, rowW, LIST_ROW)
		if hover then
			win:_rect(x + 2, ry, rowW - 4, LIST_ROW, th.ElementHover, 11, 3)
		end
		local right = tostring(item.Right or "")
		local rightW = right ~= "" and (textWidth(right, SMALL) * FIT_MARGIN + 10) or 0
		win:_text(fitText(item.Text, rowW - 16 - rightW, SMALL), x + 8, ry + (LIST_ROW - SMALL) / 2 - 1,
			item.Color or th.Text, SMALL, 12)
		if right ~= "" then
			win:_text(right, x + rowW - 8, ry + (LIST_ROW - SMALL) / 2 - 1, th.TextDim, SMALL, 12, "right")
		end
		if win:_clickIn(x, ry, rowW, LIST_ROW) then
			runCallback(self.OnClick, item)
		end
	end
end

function List:ScrollTo(index)
	self.Scroll = clamp(math.floor(index or 0), 0, self:_maxScroll())
end

function List:SetItems(items)
	self.Items = items or {}
end

--// textbox ------------------------------------------------------------------
local Textbox = {}
Textbox.__index = Textbox

function Section:AddTextbox(config)
	config = config or {}
	local box = self:_add(setmetatable({
		Text = config.Name or "Textbox",
		Value = tostring(config.Default or ""),
		Placeholder = config.Placeholder or "Type here...",
		Numeric = config.Numeric == true,
		MaxLength = tonumber(config.MaxLength) or 120,
		ClearOnFocus = config.ClearOnFocus == true,
		Live = config.Live == true, -- fire Callback on every keystroke instead of on Enter / click away
		Flag = config.Flag,
		Callback = config.Callback,
	}, Textbox))
	self:_setFlag(box.Flag, box:Get())
	self:_register(box, config)
	return box
end

function Textbox:_restore(value)
	if type(value) == "string" or type(value) == "number" then
		if tostring(value) ~= self.Value then
			self:Set(tostring(value))
		end
	end
end

function Textbox:_height()
	return 41
end

function Textbox:_focus()
	self._before = self.Value
	if self.ClearOnFocus then
		self.Value = ""
	end
	focusTarget(self.Window, self)
end

function Textbox:_unfocus(submit)
	local win = self.Window
	if win._focusedBox ~= self then
		return
	end
	win._focusedBox = nil
	if not submit then
		self.Value = self._before or self.Value -- Escape: undo the edit
		self.Section:_setFlag(self.Flag, self:Get())
		return
	end
	if self.Numeric and self.Value ~= "" and not tonumber(self.Value) then
		self.Value = self._before or ""
	end
	self.Section:_setFlag(self.Flag, self:Get())
	if not self.Live then
		runCallback(self.Callback, self:Get(), true)
	end
end

function Textbox:_changed()
	self.Section:_setFlag(self.Flag, self:Get())
	if self.Live then
		runCallback(self.Callback, self:Get(), false)
	end
end

function Textbox:_insert(char)
	if #self.Value >= self.MaxLength then
		return
	end
	if self.Numeric and not char:match("[%d%.%-]") then
		return
	end
	self.Value = self.Value .. char
	self:_changed()
end

function Textbox:_backspace()
	if self.Value == "" then
		return
	end
	self.Value = charSub(self.Value, charCount(self.Value) - 1)
	self:_changed()
end

function Textbox:_draw(win, x, y, w)
	local th = win.Theme
	local boxY, boxH = y + LABEL_GAP, 22
	local focused = win._focusedBox == self

	self._rect = { x = x, y = boxY, w = w, h = boxH }
	if win:_clickIn(x, boxY, w, boxH) and not focused then
		self:_focus()
		focused = true
	end

	win:_text(fitText(self.Text, w, TEXT), x, y, th.Text, TEXT, 12)
	local hover = win:_over(x, boxY, w, boxH)
	local fill = (hover or focused) and th.ElementHover or th.Element
	win:_box(x, boxY, w, boxH, fill, focused and th.Accent or fill, 10, 4)

	local inner = w - 16
	local textY = boxY + (boxH - SMALL) / 2 - 1
	if self.Value == "" and not focused then
		win:_text(fitText(self.Placeholder, inner, SMALL), x + 7, textY, th.TextMuted, SMALL, 12)
	else
		-- show the end of the text while typing so the caret stays visible
		-- Drawing text can't be clipped, so only show what fits (with slack for wide letters)
		local shown = self.Value
		local room = inner - 6
		if textWidth(shown, SMALL) * FIT_MARGIN > room then
			if focused then
				-- keep the end visible while typing
				local keep = #shown
				while keep > 0 and textWidth("..." .. shown:sub(-keep), SMALL) * FIT_MARGIN > room do
					keep = keep - 1
				end
				shown = "..." .. shown:sub(-math.max(keep, 0))
			else
				shown = fitText(shown, room, SMALL)
			end
		end
		win:_text(shown, x + 7, textY, th.Text, SMALL, 12)
		if focused and (os.clock() % 1) < 0.55 then
			local cx = x + 7 + textWidth(shown, SMALL) + 1
			win:_rect(cx, boxY + 4, 1, boxH - 8, th.Accent, 13)
		end
	end
end

function Textbox:Set(text)
	self.Value = tostring(text or "")
	self.Section:_setFlag(self.Flag, self:Get())
	runCallback(self.Callback, self:Get(), true)
end

function Textbox:Get()
	if self.Numeric then
		return tonumber(self.Value) or self.Value
	end
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
	self:_register(dropdown, config)
	return dropdown
end

function Dropdown:_restore(value)
	local valid = {}
	for _, o in ipairs(self._options) do
		valid[o] = true
	end
	if self.Multi then
		if type(value) ~= "table" then
			return
		end
		local list = {}
		for _, v in ipairs(value) do
			if valid[v] then
				list[#list + 1] = v
			end
		end
		if table.concat(list, "\0") ~= table.concat(self.Value, "\0") then
			self:Set(list)
		end
	elseif valid[value] and value ~= self.Value then
		self:Set(value)
	end
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
			return "None"
		end
		local parts = {}
		for i, v in ipairs(self.Value) do
			parts[i] = tostring(v)
		end
		return table.concat(parts, ", ")
	end
	if self.Value == nil then
		return "None"
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
	return 41
end

function Dropdown:_drawGrid(win, cx, cy, color, z)
	for gx = -1, 1 do
		for gy = -1, 1 do
			win:_rect(cx + gx * 4 - 1, cy + gy * 4 - 1, 2, 2, color, z)
		end
	end
end

function Dropdown:_draw(win, x, y, w)
	local th = win.Theme
	local boxY, boxH = y + LABEL_GAP, 22
	self._box = { x = x, y = boxY, w = w, h = boxH }

	local open = win._openDropdown == self
	if win:_clickIn(x, boxY, w, boxH) then
		win._openDropdown = open and nil or self
		open = not open
	end

	win:_text(fitText(self.Text, w, TEXT), x, y, th.Text, TEXT, 12)
	local hover = win:_over(x, boxY, w, boxH)
	local fill = hover and th.ElementHover or th.Element
	win:_box(x, boxY, w, boxH, fill, open and th.Accent or fill, 10, 4)
	local display = self:_display()
	win:_text(fitText(display, w - 30, SMALL), x + 7, boxY + (boxH - SMALL) / 2 - 1, display == "None" and th.TextMuted or th.Text, SMALL, 12)
	self:_drawGrid(win, x + w - 11, boxY + boxH / 2, th.Accent, 12)
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

--==============================================================================
-- Built-in "UI" tab: the same in every script (theme, font, menu key, configs)
--==============================================================================
function Window:_buildUniversalTab(opts, windowConfig)
	local window = self
	local tab = self:CreateTab({ Name = opts.Name or "UI", Icon = opts.Icon or "@", _universal = true })
	self._universalTab = tab
	self.UniversalTab = tab

	local interface = tab:CreateSection({ Name = "Interface", Side = "Left" })

	local themeNames = { "Default" }
	for name in pairs(Library.Themes) do
		if name ~= "Default" then
			themeNames[#themeNames + 1] = name
		end
	end
	table.sort(themeNames, function(a, b)
		if a == "Default" or b == "Default" then
			return a == "Default"
		end
		return a < b
	end)
	local startTheme = type(windowConfig.Theme) == "string" and windowConfig.Theme or "Default"
	interface:AddDropdown({
		Name = "Theme",
		Options = themeNames,
		Default = startTheme,
		Flag = "UI_Theme",
		Config = false,
		Callback = function(value)
			window:SetTheme(value)
		end,
	})

	local startFont = "UI"
	for name, id in pairs(FontIds) do
		if id == FONT then
			startFont = name
		end
	end
	interface:AddDropdown({
		Name = "Font",
		Options = fontNames(),
		Default = startFont,
		Flag = "UI_Font",
		Config = false,
		Callback = function(value)
			window:SetFont(value)
		end,
	})

	interface:AddKeybind({
		Name = "Menu Key",
		Default = window._toggleKey and window._toggleKey.vk or "RightShift",
		Menu = true,
		Flag = "UI_MenuKey",
		Config = false,
	})

	-- FPS cap: limits how often the UI redraws, and the game too when the executor has setfpscap
	local capOptions = { "Unlimited", "30", "60", "120", "144", "240", "360" }
	local startCap = "Unlimited"
	if window._maxFps then
		startCap = tostring(math.floor(window._maxFps))
		local listed = false
		for _, o in ipairs(capOptions) do
			listed = listed or o == startCap
		end
		if not listed then
			table.insert(capOptions, 2, startCap)
		end
	end
	interface:AddDropdown({
		Name = "FPS Cap",
		Options = capOptions,
		Default = startCap,
		Flag = "UI_FpsCap",
		Config = false,
		Callback = function(value)
			window:SetFpsCap(tonumber(value))
		end,
	})

	interface:AddToggle({
		Name = "Show Performance",
		Default = false,
		Flag = "UI_Performance",
		Config = false,
		Callback = function(on)
			window.PerformanceEnabled = on
			window._statsNext = 0
		end,
	})

	-- remembers where the performance bar was dragged to
	window:_register("UI_PerfPos", {
		_noConfig = true,
		_restore = function(_, value)
			if type(value) == "table" and type(value[1]) == "number" and type(value[2]) == "number" then
				window._perfPos = Vector2.new(value[1], value[2])
				window.Flags.UI_PerfPos = { value[1], value[2] }
			end
		end,
	})

	interface:AddToggle({
		Name = "Notifications",
		Default = true,
		Flag = "UI_Notifications",
		Config = false,
		Callback = function(on)
			window.NotificationsEnabled = on
		end,
	})

	interface:AddButton({
		Name = "Animation Tracker",
		Callback = function()
			window:OpenAnimationTracker()
		end,
	})

	interface:AddButton({
		Name = "Hide UI",
		Callback = function()
			window:Toggle(false)
		end,
	})

	local unload
	local armed = -math.huge
	unload = interface:AddButton({
		Name = "Unload",
		Callback = function()
			if now() - armed > 3 then
				armed = now()
				unload:SetText("Confirm unload")
				spawnTask(function()
					waitTask(3)
					if window.Running then
						unload:SetText("Unload")
					end
				end)
				return
			end
			runCallback(windowConfig.OnUnload)
			window:Destroy()
		end,
	})

	self:AddConfigSection(tab, "Right")
	return tab
end

--==============================================================================
-- Animation tracker (mini window): Window:OpenAnimationTracker()
--==============================================================================
-- Reading what a character is playing. In order:
--   1. Library.AnimationProvider(model) if a script sets one; return { { Id = "123", Time = 0.4, Key = track }, ... }
--   2. memory_read + offsets (Matcha), the same way as the Demon://Slayer script
--   3. Animator:GetPlayingAnimationTracks()
Library.OffsetsUrl = "https://offsets.imtheo.lol/Offsets.json"

local function toNumber(v)
	if type(v) == "number" then
		return v
	end
	if type(v) == "string" then
		return tonumber(v) or tonumber((v:gsub("^0[xX]", "")), 16)
	end
	return nil
end

local Mem = { tried = false, offsets = nil, animCache = {}, animCacheN = 0 }

function Mem.load()
	if Mem.tried then
		return Mem.offsets
	end
	Mem.tried = true
	if type(memory_read) ~= "function" then
		return nil
	end
	local ok, body = pcall(function()
		return game:HttpGet(Library.OffsetsUrl)
	end)
	local data = ok and Json.decode(body) or nil
	local o = type(data) == "table" and data.Offsets or nil
	if type(o) ~= "table" then
		log("animation tracker: couldn't download offsets")
		return nil
	end
	local function g(a, b)
		return type(o[a]) == "table" and toNumber(o[a][b]) or nil
	end
	local offsets = {
		AnimationId = g("Misc", "AnimationId"),
		ClassDescriptor = g("Instance", "ClassDescriptor"),
		ClassName = g("Instance", "ClassName"),
		TimePosition = g("AnimationTrack", "TimePosition") or 0xD8,
		ActiveAnimations = g("Animator", "ActiveAnimations"),
		Animation = g("AnimationTrack", "Animation"),
		NodeNext = 0x10,
	}
	for k, v in pairs(offsets) do
		if type(v) ~= "number" then
			log("animation tracker: offset missing:", k)
			return nil
		end
	end
	Mem.offsets = offsets
	return offsets
end

local function readPointer(addr)
	if type(addr) ~= "number" then
		return nil
	end
	local ok, v = pcall(memory_read, "uintptr_t", addr)
	if ok and type(v) == "number" and v > 4096 then
		return v
	end
	return nil
end

local function readString(addr)
	if not addr or addr <= 4096 then
		return nil
	end
	local ok, v = pcall(memory_read, "string", addr)
	return ok and v or nil
end

local function findAnimator(model)
	local holder = child(model, "Humanoid") or child(model, "AnimationController")
	return child(holder, "Animator")
end

local function memoryAnimations(model)
	local o = Mem.load()
	local animator = o and findAnimator(model)
	local addr = toNumber(prop(animator, "Address"))
	if not addr then
		return nil
	end
	local out = {}
	local head = readPointer(addr + o.ActiveAnimations)
	if not head then
		return out
	end
	local node, count = readPointer(head), 0
	while node and node ~= head and count < 50 do
		count = count + 1
		local track = readPointer(node + o.NodeNext)
		local anim = track and readPointer(track + o.Animation)
		if anim then
			local id = Mem.animCache[anim]
			if id == nil then
				id = false
				local desc = readPointer(anim + o.ClassDescriptor)
				if desc and readString(readPointer(desc + o.ClassName)) == "Animation" then
					local raw = readString(readPointer(anim + o.AnimationId))
					id = raw and tostring(raw):match("%d+") or false
				end
				if Mem.animCacheN > 800 then
					Mem.animCache, Mem.animCacheN = {}, 0
				end
				Mem.animCache[anim] = id
				Mem.animCacheN = Mem.animCacheN + 1
			end
			if id then
				local ok, t = pcall(memory_read, "float", track + o.TimePosition)
				local good = ok and type(t) == "number" and t == t and t >= 0 and t < 30
				out[#out + 1] = { Id = id, Time = good and t or 0, Key = track }
			end
		end
		node = readPointer(node)
	end
	return out
end

local apiBroken = false
local function apiAnimations(model)
	if apiBroken then
		return nil
	end
	local animator = findAnimator(model)
	if not animator then
		return nil
	end
	local ok, tracks = pcall(function()
		return animator:GetPlayingAnimationTracks()
	end)
	if not ok or type(tracks) ~= "table" then
		apiBroken = true -- don't retry every tick (Matcha prints errors even inside pcall)
		return nil
	end
	local out = {}
	for _, track in ipairs(tracks) do
		local animation = prop(track, "Animation")
		local id = tostring(prop(animation, "AnimationId") or ""):match("%d+")
		if id then
			out[#out + 1] = { Id = id, Time = toNumber(prop(track, "TimePosition")) or 0, Key = track }
		end
	end
	return out
end

function Library.GetPlayingAnimations(model)
	if type(Library.AnimationProvider) == "function" then
		local ok, list = pcall(Library.AnimationProvider, model)
		return ok and type(list) == "table" and list or {}
	end
	if type(memory_read) == "function" then
		local list = memoryAnimations(model)
		if list then
			return list
		end
	end
	return apiAnimations(model) or {}
end

-- finding characters
local function cleanModelName(name)
	return (tostring(name or ""):gsub("^%.", ""))
end

local function hasHumanoid(model)
	return child(model, "Humanoid") ~= nil or child(model, "AnimationController") ~= nil
end

-- a player's character, wherever it is in workspace
function Library.FindCharacter(name)
	local player = child(Players, name)
	local character = prop(player, "Character")
	if character and hasHumanoid(character) then
		return character
	end
	local alive = child(workspace, "Alive")
	local direct = child(alive, name) or child(alive, "." .. name) or child(workspace, name)
	if direct and hasHumanoid(direct) then
		return direct
	end
	local ok, all = pcall(function()
		return workspace:GetDescendants()
	end)
	if ok and type(all) == "table" then
		for _, v in ipairs(all) do
			local n = prop(v, "Name")
			if n and cleanModelName(n) == name and hasHumanoid(v) then
				return v
			end
		end
	end
	return nil
end

-- "Alive/NpcName", "workspace.Alive.NpcName" or just "NpcName"
function Library.FindByPath(path)
	path = tostring(path or ""):gsub("^%s+", ""):gsub("%s+$", "")
	if path == "" then
		return nil
	end
	local sep = path:find("/") and "[^/]+" or "[^%.]+"
	local parts = {}
	for part in path:gmatch(sep) do
		parts[#parts + 1] = part
	end
	local first = (parts[1] or ""):lower()
	if first == "game" then
		table.remove(parts, 1)
		first = (parts[1] or ""):lower()
	end
	if first == "workspace" then
		table.remove(parts, 1)
	end
	local function walk(list)
		local current = workspace
		for _, part in ipairs(list) do
			current = child(current, part)
			if not current then
				return nil
			end
		end
		return current
	end
	local found = walk(parts)
	if not found then
		local inAlive = { "Alive" }
		for _, part in ipairs(parts) do
			inAlive[#inAlive + 1] = part
		end
		found = walk(inAlive)
	end
	if not found and #parts == 1 then
		found = Library.FindCharacter(parts[1])
	end
	return found
end

-- world -> screen, done by hand from the camera's CFrame (works in Matcha)
local Cam = {}
function Cam.update()
	local cam = prop(workspace, "CurrentCamera")
	local vp, fov, cf = prop(cam, "ViewportSize"), prop(cam, "FieldOfView"), prop(cam, "CFrame")
	if not (vp and type(fov) == "number" and cf) then
		return false
	end
	local ok, cx, cy, cz, m00, m01, m02, m10, m11, m12, m20, m21, m22 = pcall(function()
		return cf:GetComponents()
	end)
	if not ok or type(m22) ~= "number" then
		return false
	end
	Cam.cx, Cam.cy, Cam.cz = cx, cy, cz
	Cam.m00, Cam.m01, Cam.m02 = m00, m01, m02
	Cam.m10, Cam.m11, Cam.m12 = m10, m11, m12
	Cam.m20, Cam.m21, Cam.m22 = m20, m21, m22
	Cam.hw, Cam.hh = vp.X * 0.5, vp.Y * 0.5
	Cam.focal = Cam.hh / math.tan(math.rad(fov) * 0.5)
	return true
end

function Cam.project(x, y, z)
	local dx, dy, dz = x - Cam.cx, y - Cam.cy, z - Cam.cz
	local depth = -(Cam.m02 * dx + Cam.m12 * dy + Cam.m22 * dz)
	if depth < 0.1 then
		return nil -- behind the camera
	end
	local s = Cam.focal / depth
	return Cam.hw + (Cam.m00 * dx + Cam.m10 * dy + Cam.m20 * dz) * s,
		Cam.hh - (Cam.m01 * dx + Cam.m11 * dy + Cam.m21 * dz) * s,
		depth
end

local function rootPart(model)
	return child(model, "HumanoidRootPart") or child(model, "Head") or prop(model, "PrimaryPart")
end

local function copyText(text)
	for _, name in ipairs({ "setclipboard", "toclipboard", "set_clipboard", "writeclipboard" }) do
		local fn = rawget(_G, name)
		if type(fn) ~= "function" and type(getgenv) == "function" then
			fn = rawget(getgenv(), name)
		end
		if type(fn) ~= "function" and type(getfenv) == "function" then
			local ok, env = pcall(getfenv, 0)
			if ok and type(env) == "table" then
				fn = rawget(env, name)
			end
		end
		if type(fn) == "function" and pcall(fn, text) then
			return true
		end
	end
	return false
end

function Window:OpenAnimationTracker()
	if self._tracker and self._tracker.Running then
		self._tracker:Destroy() -- the button toggles it
		return nil
	end
	local parent = self
	local vw = viewportSize()
	local tracker = Library:CreateWindow({
		Title = "Animation Tracker",
		Mini = true,
		Columns = 1,
		HideTabs = true,
		Closable = true,
		ToggleKey = false,
		Size = Vector2.new(300, 120),
	})
	tracker.Theme = parent.Theme -- same table, so theme changes apply to both
	tracker._logoData = parent._logoData
	tracker._x = parent._x + parent._width + 12
	if tracker._x + 300 > vw then
		tracker._x = math.max(0, parent._x - 312)
	end
	tracker._y = parent._y
	parent._children[#parent._children + 1] = tracker
	parent._tracker = tracker
	tracker:SetStatus("Idle", false)

	local tab = tracker:CreateTab({ Name = "Tracker" })
	local targetSec = tab:CreateSection({ Name = "Target" })
	local animSec = tab:CreateSection({ Name = "Animations" })

	local state = { targets = {}, history = {}, printing = false, esp = true }
	local typeDd, playerDd, pathBox, refreshBtn, trackToggle, list

	local function playerNames()
		local names = {}
		local ok, players = pcall(function()
			return Players:GetPlayers()
		end)
		if ok and type(players) == "table" then
			for _, p in ipairs(players) do
				local n = prop(p, "Name")
				if n then
					names[#names + 1] = n
				end
			end
		end
		table.sort(names, function(a, b)
			return a:lower() < b:lower()
		end)
		return names
	end

	local function updateVisibility()
		local kind = typeDd:Get()
		playerDd:SetVisible(kind == "Player")
		refreshBtn:SetVisible(kind == "Player")
		pathBox:SetVisible(kind == "Path")
	end

	typeDd = targetSec:AddDropdown({
		Name = "Target Type",
		Options = { "LocalPlayer", "Player", "Path" },
		Default = "LocalPlayer",
		Callback = function()
			updateVisibility()
		end,
	})
	playerDd = targetSec:AddDropdown({ Name = "Player", Options = playerNames() })
	refreshBtn = targetSec:AddButton({
		Name = "Refresh Players",
		Callback = function()
			playerDd:Refresh(playerNames(), true)
		end,
	})
	pathBox = targetSec:AddTextbox({ Name = "Path", Placeholder = "Alive/NpcName" })

	-- who to watch right now: returns a function that finds the model again (respawns)
	local function resolver()
		local kind = typeDd:Get()
		if kind == "LocalPlayer" then
			local name = prop(prop(Players, "LocalPlayer"), "Name") or "You"
			return name, function()
				return Library.FindCharacter(name)
			end
		elseif kind == "Player" then
			local name = playerDd:Get()
			if not name then
				return nil
			end
			return name, function()
				return Library.FindCharacter(name)
			end
		end
		local path = pathBox:Get()
		if path == "" then
			return nil
		end
		return path:match("([^/%.]+)$") or path, function()
			return Library.FindByPath(path)
		end
	end

	local function refreshList()
		local items = {}
		for i, e in ipairs(state.history) do
			items[i] = {
				Text = e.id,
				Right = string.format("%s x%d", e.target, e.count),
				Value = e.id,
			}
		end
		list:SetItems(items)
	end

	local function addHistory(id, targetName, t)
		if type(Library.TrackerIgnore) == "table" and Library.TrackerIgnore[id] then
			return
		end
		for i, e in ipairs(state.history) do
			if e.id == id then
				e.count = e.count + 1
				e.target = targetName
				table.remove(state.history, i)
				table.insert(state.history, 1, e)
				refreshList()
				return
			end
		end
		table.insert(state.history, 1, { id = id, count = 1, target = targetName })
		if #state.history > 50 then
			table.remove(state.history)
		end
		refreshList()
		if (list.Scroll or 0) > 0 then
			list:ScrollTo(list.Scroll + 1) -- scrolled down: keep the same rows in view
		end
		if state.printing then
			print(string.format("[UiLibrary] %s | %s | %.2fs in", targetName, id, t or 0))
		end
	end

	local function updateStatus()
		local names = {}
		for _, tgt in ipairs(state.targets) do
			names[#names + 1] = tgt.name
		end
		if #names == 0 then
			tracker:SetStatus("Idle", false)
		else
			tracker:SetStatus("Tracking " .. table.concat(names, ", "), true)
		end
	end

	trackToggle = targetSec:AddToggle({
		Name = "Tracking",
		Default = false,
		Callback = function(on)
			if not on then
				state.targets = {}
				updateStatus()
				return
			end
			local name, find = resolver()
			local model = find and find()
			if not model then
				tracker:Notify("Tracker", "Target not found: " .. tostring(name or "pick one first"), 3)
				trackToggle.Value = false
				return
			end
			state.targets = { { name = name, find = find, model = model, seen = {}, lostAt = nil } }
			updateStatus()
			tracker:Notify("Tracker", "Tracking " .. name, 2)
		end,
	})

	targetSec:AddToggle({
		Name = "Show ESP",
		Default = true,
		Callback = function(on)
			state.esp = on
		end,
	})

	list = animSec:AddList({
		Rows = 6,
		Empty = "Turn on Tracking to see animations",
		OnClick = function(item)
			if copyText(item.Value) then
				tracker:Notify("Tracker", "Copied " .. item.Value, 2)
			else
				print("[UiLibrary] animation id: " .. item.Value)
				tracker:Notify("Tracker", item.Value .. " (printed to console)", 3)
			end
		end,
	})
	animSec:AddToggle({
		Name = "Print to Console",
		Default = false,
		Callback = function(on)
			state.printing = on
		end,
	})
	animSec:AddButton({
		Name = "Copy All",
		Callback = function()
			local ids = {}
			for i, e in ipairs(state.history) do
				ids[i] = e.id
			end
			if #ids == 0 then
				return tracker:Notify("Tracker", "Nothing to copy yet", 2)
			end
			local text = table.concat(ids, "\n")
			if copyText(text) then
				tracker:Notify("Tracker", "Copied " .. #ids .. " IDs", 2)
			else
				print("[UiLibrary] animation ids:\n" .. text)
				tracker:Notify("Tracker", "Printed " .. #ids .. " IDs to console", 3)
			end
		end,
	})
	animSec:AddButton({
		Name = "Clear",
		Callback = function()
			state.history = {}
			for _, tgt in ipairs(state.targets) do
				tgt.seen = {}
			end
			refreshList()
		end,
	})
	updateVisibility()

	-- watch the targets
	spawnTask(function()
		while tracker.Running do
			for _, tgt in ipairs(state.targets) do
				local parentOk = tgt.model and prop(tgt.model, "Parent") ~= nil
				if not parentOk then
					-- died / respawned / streamed out: look for it again every second
					local t = now()
					if not tgt.lostAt or t - tgt.lostAt > 1 then
						tgt.lostAt = t
						tgt.model = tgt.find()
						tgt.seen = {}
					end
				else
					local seenNow = {}
					local playing = Library.GetPlayingAnimations(tgt.model)
					-- steady order so the ESP lines don't swap places between reads
					table.sort(playing, function(a, b)
						return tostring(a.Id) < tostring(b.Id)
					end)
					tgt.playing = playing
					for _, anim in ipairs(playing) do
						local key = anim.Key or anim.Id
						seenNow[key] = true
						if not tgt.seen[key] then
							tgt.seen[key] = true
							addHistory(tostring(anim.Id), tgt.name, anim.Time)
						end
					end
					tgt.seen = seenNow
				end
			end
			waitTask(0.05)
		end
	end)

	-- ESP: name + distance above the head, playing animations below the feet.
	-- Its own Drawing objects (not shared with the UI), centered by Drawing itself, whole
	-- pixels, and a property is only written when it changes - this keeps it steady.
	local espTexts = {}
	local function espText(i)
		local t = espTexts[i]
		if not t then
			local ok, o = pcall(Drawing.new, "Text")
			if not ok then
				return nil
			end
			t = { o = o, c = {} }
			pcall(function()
				o.Center = true
				o.Outline = true
				o.Transparency = 1
				o.ZIndex = 0
			end)
			espTexts[i] = t
		end
		return t
	end
	local function set(t, key, value)
		if t.c[key] ~= value then
			t.c[key] = value
			t.o[key] = value
		end
	end
	local function place(t, str, x, y, color, size)
		x, y = math.floor(x + 0.5), math.floor(y + 0.5)
		set(t, "Text", str)
		set(t, "Size", size)
		set(t, "Font", FONT)
		set(t, "Color", color)
		if t.c.x ~= x or t.c.y ~= y then
			t.c.x, t.c.y = x, y
			t.o.Position = Vector2.new(x, y)
		end
		set(t, "Visible", true)
	end
	local function hideFrom(n)
		for i = n, #espTexts do
			set(espTexts[i], "Visible", false)
		end
	end

	local function drawEsp()
		if not state.esp or #state.targets == 0 or not Cam.update() then
			hideFrom(1)
			return
		end
		local th = tracker.Theme
		local used = 0
		local function line(str, x, y, color, size)
			local t = espText(used + 1)
			if t then
				used = used + 1
				place(t, str, x, y, color, size)
			end
		end
		-- parts are looked up once and reused; only positions are read every frame
		local t = now()
		if not state.myRoot or t > (state.myRootAt or 0) then
			state.me = Library.FindCharacter(prop(prop(Players, "LocalPlayer"), "Name") or "")
			state.myRoot = rootPart(state.me)
			state.myRootAt = t + 1
		end
		local me = state.me
		local myPos = prop(state.myRoot, "Position")
		for _, tgt in ipairs(state.targets) do
			if tgt.partModel ~= tgt.model or not tgt.part then
				tgt.partModel = tgt.model
				tgt.part = rootPart(tgt.model)
			end
			local pos = prop(tgt.part, "Position")
			if pos then
				local hx, hy = Cam.project(pos.X, pos.Y + 3.4, pos.Z)
				local fx, fy = Cam.project(pos.X, pos.Y - 3.6, pos.Z)
				if hx and fx then
					local label = tgt.name
					if myPos and tgt.model ~= me then
						local dx, dy, dz = pos.X - myPos.X, pos.Y - myPos.Y, pos.Z - myPos.Z
						label = string.format("%s [%dm]", label, math.floor(math.sqrt(dx * dx + dy * dy + dz * dz) + 0.5))
					end
					line(label, hx, hy - 16, th.Accent, 13)
					local playing = tgt.playing or {}
					if #playing == 0 then
						line("no animations", fx, fy + 4, th.TextMuted, 12)
					end
					for i = 1, math.min(#playing, 6) do
						local anim = playing[i]
						local name = type(Library.AnimationNames) == "table" and Library.AnimationNames[tostring(anim.Id)]
						local text = string.format("%s  %.1fs", name and (name .. " " .. anim.Id) or tostring(anim.Id), anim.Time or 0)
						line(text, fx, fy + 4 + (i - 1) * 14, i == 1 and th.Text or th.TextDim, 12)
					end
					if #playing > 6 then
						line("+" .. (#playing - 6) .. " more", fx, fy + 4 + 6 * 14, th.TextMuted, 12)
					end
				end
			end
		end
		hideFrom(used + 1)
	end

	-- every frame, separate from the UI redraw
	spawnTask(function()
		while tracker.Running do
			local ok, err = pcall(drawEsp)
			if not ok and tostring(err) ~= state.espError then
				state.espError = tostring(err)
				log("tracker ESP error:", err)
			end
			waitTask()
		end
		for _, t in ipairs(espTexts) do
			pcall(function()
				t.o.Visible = false
			end)
			pcall(function()
				t.o:Remove()
			end)
		end
	end)

	tracker.State = state
	return tracker
end

--==============================================================================
-- Ready-made config section: Window:AddConfigSection(tab, side)
--==============================================================================
function Window:AddConfigSection(tab, side)
	local window = self
	local section = tab:CreateSection({ Name = "Configs", Side = side or "Right" })

	local nameBox = section:AddTextbox({
		Name = "Config Name",
		Placeholder = "Name to save / rename to",
		MaxLength = 40,
	})

	local list = section:AddDropdown({
		Name = "Configs",
		Options = window:ListConfigs(),
	})

	-- Autoload: the chosen config is loaded every time the script starts
	local function autoloadOptions()
		local options = { "None" }
		for _, name in ipairs(window:ListConfigs()) do
			options[#options + 1] = name
		end
		return options
	end
	local autoload = section:AddDropdown({
		Name = "Autoload",
		Options = autoloadOptions(),
		Default = "None",
		Flag = "UI_Autoload",
		Config = false,
	})
	local baseRestore = autoload._restore
	autoload._restore = function(self, value)
		baseRestore(self, value)
		if type(value) == "string" and value ~= "None" and self.Value == value then
			window._autoloadPending = value -- loaded after every other saved setting is back
		end
	end

	local function refresh(select)
		list:Refresh(window:ListConfigs(), true)
		if select then
			list.Value = select
		end
		autoload:Refresh(autoloadOptions(), true)
		if autoload.Value == nil then
			autoload:Set("None")
		end
	end

	local function selected()
		return list:Get()
	end

	local function report(ok, err, success)
		if ok then
			window:Notify("Configs", success, 3)
		else
			window:Notify("Configs", err or "Something went wrong", 3)
		end
	end

	section:AddButton({
		Name = "Save",
		Callback = function()
			-- save to the typed name, or overwrite the selected config
			local name = cleanName(nameBox:Get())
			if name == "" then
				name = selected() or ""
			end
			local ok, err = window:SaveConfig(name)
			report(ok, err, "Saved " .. name)
			if ok then
				refresh(name)
			end
		end,
	})

	section:AddButton({
		Name = "Load",
		Callback = function()
			local name = selected()
			if not name then
				return report(false, "Pick a config first")
			end
			local ok, err = window:LoadConfig(name)
			report(ok, err, "Loaded " .. name)
		end,
	})

	section:AddButton({
		Name = "Rename",
		Callback = function()
			local name = selected()
			if not name then
				return report(false, "Pick a config first")
			end
			local new = cleanName(nameBox:Get())
			local wasAutoload = autoload.Value == name
			local ok, err = window:RenameConfig(name, new)
			report(ok, err, "Renamed " .. name .. " to " .. new)
			if ok then
				refresh(new)
				if wasAutoload then
					autoload:Set(new)
				end
			end
		end,
	})

	local deleteButton
	local armed = -math.huge
	deleteButton = section:AddButton({
		Name = "Delete",
		Callback = function()
			local name = selected()
			if not name then
				return report(false, "Pick a config first")
			end
			-- press twice within 3 seconds to delete
			if now() - armed > 3 then
				armed = now()
				deleteButton:SetText("Confirm delete")
				spawnTask(function()
					waitTask(3)
					deleteButton:SetText("Delete")
				end)
				return
			end
			armed = -math.huge
			deleteButton:SetText("Delete")
			window:DeleteConfig(name)
			report(true, nil, "Deleted " .. name)
			list.Value = nil
			refresh()
		end,
	})

	return section
end

return Library
