--[[
	Test - example script that uses every element in UiLibrary.

	Run this file in your executor. It downloads the library from GitHub,
	builds the window, and RightShift shows / hides it.

	The callbacks here only print, notify or change the UI itself, so the demo
	works even in executors that can't touch game services.
]]

-- Matcha keeps showing errors but does not stop the script after error(), so each
-- failure below prints a message and returns.
local warn = warn or print
local URL = "https://raw.githubusercontent.com/opsecgodscripts/UiLibrary/refs/heads/main/UiLibrary/Library.lua"
local source = game:HttpGet(URL)
if type(source) ~= "string" or #source < 100 then
	warn("UiLibrary: download failed, got " .. tostring(source))
	return
end

local chunk, compileError = loadstring(source)
if type(chunk) ~= "function" then
	warn("UiLibrary: compile error: " .. tostring(compileError))
	return
end

local ok, result = pcall(chunk)
if not ok then
	warn("UiLibrary: runtime error: " .. tostring(result))
	return
end

-- Matcha can drop the return value of a loadstring chunk; the library also sets _G.UiLibrary
local Library = type(result) == "table" and result or _G.UiLibrary
if type(Library) ~= "table" and type(getgenv) == "function" then
	Library = getgenv().UiLibrary
end
if type(Library) ~= "table" then
	warn("UiLibrary: loaded " .. #source .. " bytes but got no library"
		.. (source:find("_G.UiLibrary", 1, true) and "" or " (old copy from GitHub's cache, try again in a few minutes)"))
	return
end

local playerName = "Player"
pcall(function()
	playerName = game:GetService("Players").LocalPlayer.Name
end)

local fpsRunning = false

--// Window ------------------------------------------------------------------
local Window = Library:CreateWindow({
	Title = "Tungity",
	Subtitle = "Demo",
	Logo = "https://raw.githubusercontent.com/opsecgodscripts/UiLibrary/refs/heads/main/assets/logo.png",
	ToggleKey = "RightShift", -- or "Insert", "F1", "K", or a virtual-key number like 0xA1
	Theme = "Default",        -- starting theme ("Default" or "Tung"); changeable in the UI tab
	OnUnload = function()     -- runs when Unload is pressed in the UI tab
		fpsRunning = false
	end,
	Font = "UI",             -- "UI", "Plex", "System" or "Monospace"
})

-- prints only while "Print Changes" is on
local function logChange(...)
	if Window.Flags.PrintChanges then
		print(...)
	end
end

local MainTab = Window:CreateTab({ Name = "Main", Icon = ">" })
local VisualsTab = Window:CreateTab({ Name = "Visuals", Icon = "*" })
local MiscTab = Window:CreateTab({ Name = "Misc", Icon = "#" })

--// Main tab: left section -----------------------------------------------------
local General = MainTab:CreateSection({ Name = "General", Side = "Left" })

-- Toggle: FPS counter in the footer
General:AddToggle({
	Name = "Show FPS",
	Default = false,
	Flag = "ShowFPS",
	Callback = function(enabled)
		fpsRunning = enabled
		if not enabled then
			Window:SetStatus("Connected as " .. playerName, true)
			return
		end
		local frames, started = 0, os.clock()
		while fpsRunning and Window.Running do
			task.wait()
			frames = frames + 1
			local elapsed = os.clock() - started
			if elapsed >= 0.5 then
				Window:SetStatus(string.format("%d FPS", frames / elapsed), true)
				frames, started = 0, os.clock()
			end
		end
	end,
})

-- Toggle with a keybind: press P (even with the UI hidden) to flip it
General:AddToggle({
	Name = "Print Changes",
	Default = false,
	Flag = "PrintChanges",
	Keybind = "P",
	Callback = function(enabled)
		print("Print changes:", enabled and "on" or "off")
	end,
})

General:AddButton({
	Name = "Send Test Notification",
	Callback = function()
		Window:Notify("Hello", "This is a notification from test.lua", 3)
	end,
})

-- A toggle that starts on
General:AddToggle({
	Name = "Notify on Click",
	Default = true,
	Flag = "NotifyOnClick",
})

General:AddButton({
	Name = "Print Flags",
	Callback = function()
		for flag, value in pairs(Window.Flags) do
			print(flag, "=", type(value) == "table" and table.concat(value, ", ") or tostring(value))
		end
		if Window.Flags.NotifyOnClick then
			Window:Notify("Flags", "Printed every flag to the console", 3)
		end
	end,
})

-- Standalone keybinds
General:AddKeybind({
	Name = "Notify Key",
	Default = "N",
	Mode = "Press",
	Flag = "NotifyKey",
	Callback = function()
		Window:Notify("Keybind", "You pressed the notify key", 2)
	end,
})

General:AddKeybind({
	Name = "Hold Key",
	Default = "None", -- unbound until you click the box and press a key
	Mode = "Hold",
	Callback = function(held)
		Window:SetStatus(held and "Holding..." or ("Connected as " .. playerName), true)
	end,
})

--// Main tab: right section ----------------------------------------------------
local Options = MainTab:CreateSection({ Name = "Options", Side = "Right" })

Options:AddToggle({
	Name = "Enable Options",
	Default = true,
	Flag = "EnableOptions",
})

-- Multi-select dropdown
Options:AddDropdown({
	Name = "Favorite Colors",
	Options = { "Red", "Blue", "Green", "Purple", "Orange" },
	Multi = true,
	Default = { "Red", "Purple" },
	Flag = "Colors",
	Callback = function(values)
		logChange("Colors:", table.concat(values, ", "))
	end,
})

-- Dropdown with nothing selected shows "None"
Options:AddDropdown({
	Name = "Mode",
	Options = { "Easy", "Normal", "Hard" },
	Flag = "Mode",
	Callback = function(value)
		logChange("Mode:", value)
	end,
})

Options:AddDropdown({
	Name = "Greeting",
	Options = { "Hello", "Hi", "Hey", "Yo" },
	Default = "Hello",
	Flag = "Greeting",
	Callback = function(value)
		logChange("Greeting set to", value)
	end,
})

-- Sliders with a suffix
Options:AddSlider({
	Name = "Volume",
	Min = 0,
	Max = 100,
	Default = 30,
	Suffix = "%",
	Flag = "Volume",
	Callback = function(value)
		logChange("Volume", value)
	end,
})

-- Slider with decimals
Options:AddSlider({
	Name = "Speed",
	Min = 0,
	Max = 5,
	Increment = 0.1,
	Default = 1,
	Suffix = "x",
	Flag = "Speed",
})

-- Textboxes: Callback fires on Enter or when you click away
Options:AddTextbox({
	Name = "Nickname",
	Placeholder = "Type a name...",
	Flag = "Nickname",
	Callback = function(text)
		Window:Notify("Nickname", "Set to " .. (text ~= "" and text or "(empty)"), 3)
	end,
})

Options:AddTextbox({
	Name = "Walk Speed",
	Default = "16",
	Numeric = true,
	Flag = "WalkSpeedValue",
	Callback = function(value)
		logChange("Number entered:", value)
	end,
})

--// Visuals tab --------------------------------------------------------------
local Info = VisualsTab:CreateSection({ Name = "Info", Side = "Left" })
local counterLabel = Info:AddLabel("Button pressed 0 times")
local presses = 0
local counterButton
counterButton = Info:AddButton({
	Name = "Press me",
	Callback = function()
		presses = presses + 1
		counterLabel:Set("Button pressed " .. presses .. " times")
		counterButton:SetText("Pressed " .. presses .. "x")
	end,
})

local Help = VisualsTab:CreateSection({ Name = "Tips", Side = "Right" })
Help:AddLabel("Theme, font, menu key, performance bar, notifications and configs are in the UI tab (@), which every script gets automatically.")
Help:AddLabel("Click a key box, then press a key to rebind. Escape cancels, Backspace clears.")
Help:AddLabel("Anything with a Flag is saved and comes back when you run the script again.")

--// Misc tab: settings for this script (the UI tab has the ones every script shares)
local ScriptSettings = MiscTab:CreateSection({ Name = "Script", Side = "Left" })

ScriptSettings:AddSlider({
	Name = "Notification Time",
	Min = 1,
	Max = 10,
	Default = 3,
	Suffix = "s",
	Flag = "NotifyTime",
})

ScriptSettings:AddToggle({
	Name = "Welcome Message",
	Default = true,
	Flag = "WelcomeMessage",
})

ScriptSettings:AddButton({
	Name = "Test Notification",
	Callback = function()
		Window:Notify("Settings", "This stays for " .. Window.Flags.NotifyTime .. " seconds", Window.Flags.NotifyTime)
	end,
})

local About = MiscTab:CreateSection({ Name = "About", Side = "Right" })
About:AddLabel("Settings here belong to this script. Theme, font, menu key and configs are in the UI tab.")

-- The footer starts as "Disconnected" with a red dot; this turns it green.
Window:SetStatus("Connected as " .. playerName, true)
-- saved settings are applied right after the script builds the UI, so wait a moment
task.spawn(function()
	task.wait(0.1)
	if Window.Running and Window.Flags.WelcomeMessage then
		Window:Notify("Loaded", "UiLibrary is ready. RightShift hides it.", Window.Flags.NotifyTime or 3)
	end
end)
