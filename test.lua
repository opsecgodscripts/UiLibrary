--[[
	Test — example script that uses every element in UiLibrary.

	In Roblox Studio:
	  1. Make a ModuleScript in ReplicatedStorage named exactly "Library"
	     and paste UiLibrary/Library.lua into it.
	  2. Make a LocalScript in StarterPlayer > StarterPlayerScripts
	     and paste this file into it.
	  3. Play. Press RightShift to show / hide the window.

	If nothing appears, check the Output window for
	"Infinite yield possible on 'ReplicatedStorage:WaitForChild("Library")'".
	That means the ModuleScript is missing, misnamed or in the wrong place.
]]

local Players = game:GetService("Players")
local Lighting = game:GetService("Lighting")
local RunService = game:GetService("RunService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Library = require(ReplicatedStorage:WaitForChild("Library"))

local Player = Players.LocalPlayer
local Camera = workspace.CurrentCamera

--// Window ------------------------------------------------------------------
local Window = Library:CreateWindow({
	Title = "Niph",
	Subtitle = "Demo",
	ToggleKey = Enum.KeyCode.RightShift,
	-- Logo = "rbxassetid://0000000", -- optional image instead of the default mark
})

-- Icons can be a short text glyph or an image: Icon = "rbxassetid://123"
local MainTab = Window:CreateTab({ Name = "Main", Icon = "◆" })
local VisualsTab = Window:CreateTab({ Name = "Visuals", Icon = "◉" })
local SettingsTab = Window:CreateTab({ Name = "Settings", Icon = "≡" })

--// Main tab: left section -----------------------------------------------------
local General = MainTab:CreateSection({ Name = "General", Side = "Left", Icon = "✦" })

-- Toggle: FPS counter in the footer
local fpsConnection
General:AddToggle({
	Name = "Show FPS",
	Default = false,
	Flag = "ShowFPS",
	Callback = function(enabled)
		if fpsConnection then
			fpsConnection:Disconnect()
			fpsConnection = nil
		end
		if enabled then
			local frames, elapsed = 0, 0
			fpsConnection = RunService.RenderStepped:Connect(function(dt)
				frames += 1
				elapsed += dt
				if elapsed >= 0.5 then
					Window:SetStatus(string.format("%d FPS", frames / elapsed), true)
					frames, elapsed = 0, 0
				end
			end)
		else
			Window:SetStatus("Connected as " .. Player.Name, true)
		end
	end,
})

General:AddToggle({
	Name = "Print Chat Messages",
	Default = false,
	Flag = "PrintChat",
	Callback = function(enabled)
		print("Print chat messages:", enabled)
	end,
})

General:AddToggle({
	Name = "Hide Player List",
	Default = false,
	Flag = "HidePlayerList",
	Callback = function(enabled)
		game:GetService("StarterGui"):SetCoreGuiEnabled(Enum.CoreGuiType.PlayerList, not enabled)
	end,
})

-- Button between toggles, like the reference layout
General:AddButton({
	Name = "Send Test Notification",
	Callback = function()
		Window:Notify("Hello", "This is a notification from Test.lua", 3)
	end,
})

General:AddToggle({
	Name = "Shadows",
	Default = Lighting.GlobalShadows,
	Flag = "Shadows",
	Callback = function(enabled)
		Lighting.GlobalShadows = enabled
	end,
})

-- A toggle that starts on
General:AddToggle({
	Name = "Notify on Join",
	Default = true,
	Flag = "NotifyOnJoin",
})

Players.PlayerAdded:Connect(function(newPlayer)
	if Window.Flags.NotifyOnJoin then
		Window:Notify("Player joined", newPlayer.Name, 3)
	end
end)

General:AddButton({
	Name = "Print Flags",
	Callback = function()
		for flag, value in pairs(Window.Flags) do
			print(flag, "=", typeof(value) == "table" and table.concat(value, ", ") or tostring(value))
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

-- Single-select dropdowns
Options:AddDropdown({
	Name = "Greeting",
	Options = { "Hello", "Hi", "Hey", "Yo" },
	Default = "Hello",
	Flag = "Greeting",
	Callback = function(value)
		print("Greeting set to", value)
	end,
})

Options:AddDropdown({
	Name = "Start From",
	Options = { "Top", "Middle", "Bottom" },
	Default = "Top",
	Flag = "StartFrom",
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

Options:AddSlider({
	Name = "Max Zoom",
	Min = 10,
	Max = 400,
	Default = Player.CameraMaxZoomDistance,
	Suffix = " studs",
	Flag = "MaxZoom",
	Callback = function(value)
		Player.CameraMaxZoomDistance = value
	end,
})

--// Visuals tab --------------------------------------------------------------
local CameraSection = VisualsTab:CreateSection({ Name = "Camera", Side = "Left", Icon = "◉" })

CameraSection:AddSlider({
	Name = "Field of View",
	Min = 50,
	Max = 120,
	Default = Camera.FieldOfView,
	Suffix = "°",
	Callback = function(value)
		Camera.FieldOfView = value
	end,
})

local World = VisualsTab:CreateSection({ Name = "World", Side = "Right", Icon = "✦" })

local times = { Morning = 7, Noon = 12, Evening = 18, Night = 0 }
World:AddDropdown({
	Name = "Time of Day",
	Options = { "Morning", "Noon", "Evening", "Night" },
	Callback = function(value)
		Lighting.ClockTime = times[value]
	end,
})

-- Slider with decimals
World:AddSlider({
	Name = "Brightness",
	Min = 0,
	Max = 5,
	Increment = 0.1,
	Default = Lighting.Brightness,
	Callback = function(value)
		Lighting.Brightness = value
	end,
})

--// Settings tab -------------------------------------------------------------
local Interface = SettingsTab:CreateSection({ Name = "Interface", Side = "Left", Icon = "≡" })

Interface:AddLabel("Press RightShift to show or hide this window.")

Interface:AddButton({
	Name = "Destroy UI",
	Callback = function()
		if fpsConnection then
			fpsConnection:Disconnect()
		end
		Window:Destroy()
	end,
})

-- The footer starts as "Disconnected" with a red dot; this turns it green.
Window:SetStatus("Connected as " .. Player.Name, true)
