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

--// Window ------------------------------------------------------------------
local Window = Library:CreateWindow({
	Title = "Tungity",
	Subtitle = "Demo",
	Logo = "https://raw.githubusercontent.com/opsecgodscripts/UiLibrary/refs/heads/main/assets/logo.png",
	ToggleKey = "RightShift", -- or "Insert", "F1", "K", or a virtual-key number like 0xA1
	Font = "UI",             -- "UI", "Plex", "System" or "Monospace"
})

local MainTab = Window:CreateTab({ Name = "Main", Icon = ">" })
local VisualsTab = Window:CreateTab({ Name = "Visuals", Icon = "*" })
local SettingsTab = Window:CreateTab({ Name = "Settings", Icon = "#" })

--// Main tab: left section -----------------------------------------------------
local General = MainTab:CreateSection({ Name = "General", Side = "Left", Icon = "+" })

-- Toggle: FPS counter in the footer
local fpsRunning = false
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

General:AddToggle({
	Name = "Print Changes",
	Default = false,
	Flag = "PrintChanges",
	Callback = function(enabled)
		print("Print changes:", enabled)
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

--// Main tab: right section ----------------------------------------------------
local Options = MainTab:CreateSection({ Name = "Options", Side = "Right", Icon = "+" })

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
		print("Colors:", table.concat(values, ", "))
	end,
})

-- Dropdown with nothing selected shows "--"
Options:AddDropdown({
	Name = "Mode",
	Options = { "Easy", "Normal", "Hard" },
	Flag = "Mode",
	Callback = function(value)
		print("Mode:", value)
	end,
})

Options:AddDropdown({
	Name = "Greeting",
	Options = { "Hello", "Hi", "Hey", "Yo" },
	Default = "Hello",
	Flag = "Greeting",
	Callback = function(value)
		print("Greeting set to", value)
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
		print("Volume", value)
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
		print("Number entered:", value)
	end,
})

--// Visuals tab --------------------------------------------------------------
local Look = VisualsTab:CreateSection({ Name = "Look", Side = "Left", Icon = "*" })

-- Changing the theme at runtime: everything is redrawn every frame
local accents = {
	Pink = Color3.fromRGB(214, 72, 104),
	Purple = Color3.fromRGB(125, 85, 255),
	Blue = Color3.fromRGB(70, 130, 240),
	Green = Color3.fromRGB(70, 190, 120),
}
Look:AddDropdown({
	Name = "Accent Color",
	Options = { "Pink", "Purple", "Blue", "Green" },
	Default = "Pink",
	Callback = function(value)
		Window.Theme.Accent = accents[value]
	end,
})

Look:AddLabel("The accent color updates instantly.")

local Info = VisualsTab:CreateSection({ Name = "Info", Side = "Right", Icon = "*" })
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

--// Settings tab -------------------------------------------------------------
local Interface = SettingsTab:CreateSection({ Name = "Interface", Side = "Left", Icon = "#" })

Interface:AddLabel("Press RightShift to show or hide this window. Drag it by the top bar.")

Interface:AddButton({
	Name = "Hide UI",
	Callback = function()
		Window:Toggle(false)
	end,
})

Interface:AddButton({
	Name = "Unload",
	Callback = function()
		fpsRunning = false
		Window:Destroy()
	end,
})

-- The footer starts as "Disconnected" with a red dot; this turns it green.
Window:SetStatus("Connected as " .. playerName, true)
Window:Notify("Loaded", "UiLibrary is ready. RightShift hides it.", 4)
