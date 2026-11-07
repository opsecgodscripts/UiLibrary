--[[
	UiLibrary — a dark, two-column UI library for Roblox.

	Load it straight from GitHub:

	  local Library = loadstring(game:HttpGet(
	      "https://raw.githubusercontent.com/opsecgodscripts/UiLibrary/main/UiLibrary/Library.lua"
	  ))()

	See test.lua for every element.

	API
	  Library:CreateWindow({ Title, Subtitle, ToggleKey, Size, Logo, Theme })
	    Window:CreateTab({ Name, Icon })            -> Tab
	    Window:SetStatus(text, connected)           -- footer dot + text
	    Window:Notify(title, text, duration)
	    Window:SelectTab(tab)
	    Window:Toggle([visible])
	    Window:Destroy()
	    Window.Flags[flag]                          -- current value of every flagged element

	  Tab:CreateSection({ Name, Side = "Left" | "Right", Icon }) -> Section

	  Section:AddToggle({ Name, Default, Flag, Callback })              -> :Set(bool) :Get()
	  Section:AddButton({ Name, Callback })                             -> :SetText(text)
	  Section:AddLabel(text)                                            -> :Set(text)
	  Section:AddSlider({ Name, Min, Max, Default, Increment, Suffix, Flag, Callback })
	                                                                    -> :Set(number) :Get()
	  Section:AddDropdown({ Name, Options, Default, Multi, Flag, Callback })
	                                                                    -> :Set(value) :Get() :Refresh(options)

	Callbacks only fire when the user changes a value or you call :Set(), not when
	the element is created.

	Icons: pass "rbxassetid://123" for an image, or a short text glyph.
]]

local Players = game:GetService("Players")
local UserInputService = game:GetService("UserInputService")
local TweenService = game:GetService("TweenService")

local Library = {}
Library.__index = Library

--// where the ScreenGui goes: gethui() if available, then CoreGui, then PlayerGui
local function getGuiParent()
	if typeof(gethui) == "function" then
		local ok, holder = pcall(gethui)
		if ok and typeof(holder) == "Instance" then
			return holder
		end
	end
	local ok, coreGui = pcall(function()
		local cg = game:GetService("CoreGui")
		local _ = cg:GetChildren() -- errors if this context can't touch CoreGui
		return cg
	end)
	if ok and coreGui then
		return coreGui
	end
	return Players.LocalPlayer:WaitForChild("PlayerGui")
end

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

local FONT = Enum.Font.GothamMedium
local FONT_BOLD = Enum.Font.GothamBold

local FAST = TweenInfo.new(0.15, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)

--// helpers -----------------------------------------------------------------

local function create(className, props, children)
	local inst = Instance.new(className)
	for key, value in pairs(props or {}) do
		if key ~= "Parent" then
			inst[key] = value
		end
	end
	for _, child in ipairs(children or {}) do
		child.Parent = inst
	end
	if props and props.Parent then
		inst.Parent = props.Parent
	end
	return inst
end

local function corner(radius)
	return create("UICorner", { CornerRadius = UDim.new(0, radius) })
end

local function stroke(color, thickness)
	return create("UIStroke", {
		Color = color,
		Thickness = thickness or 1,
		ApplyStrokeMode = Enum.ApplyStrokeMode.Border,
	})
end

local function padding(top, right, bottom, left)
	return create("UIPadding", {
		PaddingTop = UDim.new(0, top),
		PaddingRight = UDim.new(0, right or top),
		PaddingBottom = UDim.new(0, bottom or top),
		PaddingLeft = UDim.new(0, left or right or top),
	})
end

local function tween(inst, props, info)
	local t = TweenService:Create(inst, info or FAST, props)
	t:Play()
	return t
end

local function icon(value, color, size)
	if type(value) ~= "string" or value == "" then
		return nil
	end
	if value:find("rbxasset") or value:match("^%d+$") then
		local id = value:match("^%d+$") and ("rbxassetid://" .. value) or value
		return create("ImageLabel", {
			Name = "Icon",
			BackgroundTransparency = 1,
			Size = UDim2.fromOffset(size, size),
			Image = id,
			ImageColor3 = color,
		})
	end
	return create("TextLabel", {
		Name = "Icon",
		BackgroundTransparency = 1,
		Size = UDim2.fromOffset(size, size),
		Font = FONT_BOLD,
		Text = value,
		TextSize = size - 2,
		TextColor3 = color,
	})
end

local function safeCall(callback, ...)
	if type(callback) == "function" then
		task.spawn(callback, ...)
	end
end

local function round(value, increment)
	return math.floor(value / increment + 0.5) * increment
end

local function decimalsOf(increment)
	local text = tostring(increment)
	local dot = text:find("%.")
	return dot and (#text - dot) or 0
end

--// window ------------------------------------------------------------------

function Library:CreateWindow(config)
	config = config or {}
	local theme = table.clone(DefaultTheme)
	for key, value in pairs(config.Theme or {}) do
		theme[key] = value
	end

	local Window = {
		Flags = {},
		Tabs = {},
		Theme = theme,
		_connections = {},
		_order = 0,
	}
	setmetatable(Window, { __index = Library })

	local function connect(signal, fn)
		local c = signal:Connect(fn)
		table.insert(Window._connections, c)
		return c
	end
	Window._connect = connect

	local player = Players.LocalPlayer
	local size = config.Size or UDim2.fromOffset(470, 580)

	local gui = create("ScreenGui", {
		Name = config.Title or "UiLibrary",
		ResetOnSpawn = false,
		ZIndexBehavior = Enum.ZIndexBehavior.Sibling,
		DisplayOrder = 100,
		IgnoreGuiInset = true,
	})

	local main = create("Frame", {
		Name = "Main",
		Parent = gui,
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.5),
		Size = size,
		BackgroundColor3 = theme.Background,
		BorderSizePixel = 0,
	}, { corner(8), stroke(theme.Border) })

	--// top bar
	local topbar = create("Frame", {
		Name = "Topbar",
		Parent = main,
		Size = UDim2.new(1, 0, 0, 46),
		BackgroundTransparency = 1,
	}, { padding(0, 12, 0, 14) })

	local brand = create("Frame", {
		Name = "Brand",
		Parent = topbar,
		Size = UDim2.new(0.45, 0, 1, 0),
		BackgroundTransparency = 1,
	}, {
		create("UIListLayout", {
			FillDirection = Enum.FillDirection.Horizontal,
			VerticalAlignment = Enum.VerticalAlignment.Center,
			Padding = UDim.new(0, 7),
			SortOrder = Enum.SortOrder.LayoutOrder,
		}),
	})

	local logo = icon(config.Logo, theme.Accent, 18)
	if logo then
		logo.LayoutOrder = 1
		logo.Parent = brand
	else
		-- default mark: two small rotated squares in the accent colour
		local holder = create("Frame", {
			Name = "Logo",
			Parent = brand,
			LayoutOrder = 1,
			Size = UDim2.fromOffset(18, 18),
			BackgroundTransparency = 1,
		})
		create("Frame", {
			Parent = holder,
			AnchorPoint = Vector2.new(0.5, 0.5),
			Position = UDim2.fromOffset(7, 9),
			Size = UDim2.fromOffset(9, 9),
			Rotation = 45,
			BackgroundColor3 = theme.Accent,
			BorderSizePixel = 0,
		}, { corner(2) })
		create("Frame", {
			Parent = holder,
			AnchorPoint = Vector2.new(0.5, 0.5),
			Position = UDim2.fromOffset(13, 7),
			Size = UDim2.fromOffset(6, 6),
			Rotation = 45,
			BackgroundColor3 = theme.AccentSoft,
			BorderSizePixel = 0,
		}, { corner(1) })
	end

	local titleLabel = create("TextLabel", {
		Name = "Title",
		Parent = brand,
		LayoutOrder = 2,
		AutomaticSize = Enum.AutomaticSize.X,
		Size = UDim2.fromOffset(0, 20),
		BackgroundTransparency = 1,
		Font = FONT_BOLD,
		Text = config.Title or "UiLibrary",
		TextSize = 14,
		TextColor3 = theme.Text,
	})

	local subtitleLabel = create("TextLabel", {
		Name = "Subtitle",
		Parent = brand,
		LayoutOrder = 3,
		AutomaticSize = Enum.AutomaticSize.X,
		Size = UDim2.fromOffset(0, 20),
		BackgroundTransparency = 1,
		Font = FONT,
		Text = config.Subtitle or "",
		TextSize = 11,
		TextColor3 = theme.TextMuted,
		Visible = (config.Subtitle or "") ~= "",
	})

	local tabBar = create("Frame", {
		Name = "Tabs",
		Parent = topbar,
		AnchorPoint = Vector2.new(1, 0),
		Position = UDim2.fromScale(1, 0),
		Size = UDim2.new(0.55, 0, 1, 0),
		BackgroundTransparency = 1,
	}, {
		create("UIListLayout", {
			FillDirection = Enum.FillDirection.Horizontal,
			HorizontalAlignment = Enum.HorizontalAlignment.Right,
			VerticalAlignment = Enum.VerticalAlignment.Center,
			Padding = UDim.new(0, 4),
			SortOrder = Enum.SortOrder.LayoutOrder,
		}),
	})

	create("Frame", {
		Name = "Divider",
		Parent = main,
		Position = UDim2.fromOffset(0, 46),
		Size = UDim2.new(1, 0, 0, 1),
		BackgroundColor3 = theme.Border,
		BorderSizePixel = 0,
	})

	--// pages
	local pages = create("Frame", {
		Name = "Pages",
		Parent = main,
		Position = UDim2.fromOffset(0, 47),
		Size = UDim2.new(1, 0, 1, -47 - 26),
		BackgroundTransparency = 1,
		ClipsDescendants = true,
	})

	--// footer
	local footer = create("Frame", {
		Name = "Footer",
		Parent = main,
		AnchorPoint = Vector2.new(0, 1),
		Position = UDim2.fromScale(0, 1),
		Size = UDim2.new(1, 0, 0, 26),
		BackgroundColor3 = theme.Section,
		BorderSizePixel = 0,
	}, { corner(8) })
	-- square off the footer's top corners
	create("Frame", {
		Parent = footer,
		Size = UDim2.new(1, 0, 0, 8),
		BackgroundColor3 = theme.Section,
		BorderSizePixel = 0,
	})
	create("Frame", {
		Parent = footer,
		Size = UDim2.new(1, 0, 0, 1),
		BackgroundColor3 = theme.Border,
		BorderSizePixel = 0,
	})

	local statusDot = create("Frame", {
		Name = "StatusDot",
		Parent = footer,
		AnchorPoint = Vector2.new(0, 0.5),
		Position = UDim2.new(0, 12, 0.5, 0),
		Size = UDim2.fromOffset(7, 7),
		BackgroundColor3 = theme.Bad,
		BorderSizePixel = 0,
	}, { corner(4) })

	local statusText = create("TextLabel", {
		Name = "Status",
		Parent = footer,
		AnchorPoint = Vector2.new(0, 0.5),
		Position = UDim2.new(0, 25, 0.5, 0),
		Size = UDim2.new(1, -37, 0, 16),
		BackgroundTransparency = 1,
		Font = FONT,
		Text = "Disconnected",
		TextSize = 11,
		TextColor3 = theme.TextDim,
		TextXAlignment = Enum.TextXAlignment.Left,
		TextTruncate = Enum.TextTruncate.AtEnd,
	})

	--// notifications
	local notifyHolder = create("Frame", {
		Name = "Notifications",
		Parent = gui,
		AnchorPoint = Vector2.new(1, 1),
		Position = UDim2.new(1, -16, 1, -16),
		Size = UDim2.fromOffset(260, 400),
		BackgroundTransparency = 1,
	}, {
		create("UIListLayout", {
			VerticalAlignment = Enum.VerticalAlignment.Bottom,
			Padding = UDim.new(0, 8),
			SortOrder = Enum.SortOrder.LayoutOrder,
		}),
	})

	Window._gui = gui
	Window._main = main
	Window._pages = pages
	Window._tabBar = tabBar
	Window._statusDot = statusDot
	Window._statusText = statusText
	Window._notifyHolder = notifyHolder
	Window._titleLabel = titleLabel
	Window._subtitleLabel = subtitleLabel

	--// dragging by the top bar
	local dragging, dragStart, startPos
	connect(topbar.InputBegan, function(input)
		if input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch then
			dragging = true
			dragStart = input.Position
			startPos = main.Position
		end
	end)
	connect(UserInputService.InputChanged, function(input)
		if dragging and (input.UserInputType == Enum.UserInputType.MouseMovement or input.UserInputType == Enum.UserInputType.Touch) then
			local delta = input.Position - dragStart
			main.Position = UDim2.new(startPos.X.Scale, startPos.X.Offset + delta.X, startPos.Y.Scale, startPos.Y.Offset + delta.Y)
		end
	end)
	connect(UserInputService.InputEnded, function(input)
		if input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch then
			dragging = false
		end
	end)

	--// show / hide key
	local toggleKey = config.ToggleKey or Enum.KeyCode.RightShift
	connect(UserInputService.InputBegan, function(input, processed)
		if not processed and input.KeyCode == toggleKey then
			Window:Toggle()
		end
	end)

	-- running the script again replaces the old window instead of stacking a second one
	local parent = getGuiParent()
	local existing = parent:FindFirstChild(gui.Name)
	if existing and existing:IsA("ScreenGui") then
		existing:Destroy()
	end
	gui.Parent = parent
	return Window
end

function Library:Toggle(visible)
	if visible == nil then
		visible = not self._main.Visible
	end
	self._main.Visible = visible
end

function Library:SetStatus(text, connected)
	self._statusText.Text = tostring(text)
	tween(self._statusDot, { BackgroundColor3 = connected and self.Theme.Good or self.Theme.Bad })
end

function Library:SetTitle(title, subtitle)
	if title then
		self._titleLabel.Text = title
	end
	if subtitle then
		self._subtitleLabel.Text = subtitle
		self._subtitleLabel.Visible = subtitle ~= ""
	end
end

function Library:Notify(title, text, duration)
	local theme = self.Theme
	self._order = self._order + 1

	local card = create("Frame", {
		Name = "Notification",
		Parent = self._notifyHolder,
		LayoutOrder = self._order,
		AutomaticSize = Enum.AutomaticSize.Y,
		Size = UDim2.new(1, 0, 0, 0),
		BackgroundColor3 = theme.Background,
		BackgroundTransparency = 1,
		BorderSizePixel = 0,
	}, { corner(6) })
	local border = stroke(theme.Border)
	border.Transparency = 1
	border.Parent = card

	-- accent bar down the left edge
	local bar = create("Frame", {
		Parent = card,
		Position = UDim2.fromOffset(0, 8),
		Size = UDim2.new(0, 2, 1, -16),
		BackgroundColor3 = theme.Accent,
		BackgroundTransparency = 1,
		BorderSizePixel = 0,
	})

	local content = create("Frame", {
		Name = "Content",
		Parent = card,
		AutomaticSize = Enum.AutomaticSize.Y,
		Size = UDim2.new(1, 0, 0, 0),
		BackgroundTransparency = 1,
	}, {
		padding(10, 12, 10, 14),
		create("UIListLayout", { Padding = UDim.new(0, 3), SortOrder = Enum.SortOrder.LayoutOrder }),
	})

	local titleLabel = create("TextLabel", {
		Parent = content,
		LayoutOrder = 1,
		AutomaticSize = Enum.AutomaticSize.Y,
		Size = UDim2.new(1, 0, 0, 0),
		BackgroundTransparency = 1,
		Font = FONT_BOLD,
		Text = tostring(title or ""),
		TextSize = 13,
		TextColor3 = theme.Text,
		TextTransparency = 1,
		TextWrapped = true,
		TextXAlignment = Enum.TextXAlignment.Left,
	})
	local bodyLabel = create("TextLabel", {
		Parent = content,
		LayoutOrder = 2,
		AutomaticSize = Enum.AutomaticSize.Y,
		Size = UDim2.new(1, 0, 0, 0),
		BackgroundTransparency = 1,
		Font = FONT,
		Text = tostring(text or ""),
		TextSize = 12,
		TextColor3 = theme.TextDim,
		TextTransparency = 1,
		TextWrapped = true,
		TextXAlignment = Enum.TextXAlignment.Left,
	})

	tween(card, { BackgroundTransparency = 0 })
	tween(border, { Transparency = 0 })
	tween(bar, { BackgroundTransparency = 0 })
	tween(titleLabel, { TextTransparency = 0 })
	tween(bodyLabel, { TextTransparency = 0 })

	task.delay(duration or 4, function()
		if not card.Parent then
			return
		end
		tween(card, { BackgroundTransparency = 1 })
		tween(border, { Transparency = 1 })
		tween(bar, { BackgroundTransparency = 1 })
		tween(titleLabel, { TextTransparency = 1 })
		tween(bodyLabel, { TextTransparency = 1 })
		task.wait(0.2)
		card:Destroy()
	end)
end

function Library:Destroy()
	for _, c in ipairs(self._connections) do
		c:Disconnect()
	end
	table.clear(self._connections)
	if self._gui then
		self._gui:Destroy()
	end
end

--// tabs --------------------------------------------------------------------

local Tab = {}
Tab.__index = Tab

function Library:CreateTab(config)
	config = config or {}
	local theme = self.Theme
	local window = self

	local button = create("TextButton", {
		Name = config.Name or "Tab",
		Parent = self._tabBar,
		LayoutOrder = #self.Tabs + 1,
		AutomaticSize = Enum.AutomaticSize.X,
		Size = UDim2.fromOffset(28, 28),
		BackgroundColor3 = theme.Element,
		BackgroundTransparency = 1,
		AutoButtonColor = false,
		Text = "",
	}, {
		corner(14),
		padding(0, 9, 0, 9),
		create("UIListLayout", {
			FillDirection = Enum.FillDirection.Horizontal,
			HorizontalAlignment = Enum.HorizontalAlignment.Center,
			VerticalAlignment = Enum.VerticalAlignment.Center,
			Padding = UDim.new(0, 6),
			SortOrder = Enum.SortOrder.LayoutOrder,
		}),
	})

	local tabIcon = icon(config.Icon, theme.TextMuted, 14)
	if tabIcon then
		tabIcon.LayoutOrder = 1
		tabIcon.Parent = button
	end

	local nameLabel = create("TextLabel", {
		Name = "Label",
		Parent = button,
		LayoutOrder = 2,
		AutomaticSize = Enum.AutomaticSize.X,
		Size = UDim2.fromOffset(0, 16),
		BackgroundTransparency = 1,
		Font = FONT,
		Text = config.Name or "Tab",
		TextSize = 12,
		TextColor3 = theme.Text,
		-- like the reference design, inactive tabs show only their icon
		Visible = tabIcon == nil,
	})

	local page = create("Frame", {
		Name = config.Name or "Page",
		Parent = self._pages,
		Size = UDim2.fromScale(1, 1),
		BackgroundTransparency = 1,
		Visible = false,
	})

	local function column(name, anchorX, posX)
		return create("ScrollingFrame", {
			Name = name,
			Parent = page,
			AnchorPoint = Vector2.new(anchorX, 0),
			Position = UDim2.new(posX, 0, 0, 0),
			Size = UDim2.new(0.5, 0, 1, 0),
			BackgroundTransparency = 1,
			BorderSizePixel = 0,
			CanvasSize = UDim2.new(),
			AutomaticCanvasSize = Enum.AutomaticSize.Y,
			ScrollingDirection = Enum.ScrollingDirection.Y,
			ScrollBarThickness = 2,
			ScrollBarImageColor3 = theme.Border,
			ElasticBehavior = Enum.ElasticBehavior.Never,
		}, {
			padding(10, anchorX == 0 and 5 or 10, 10, anchorX == 0 and 10 or 5),
			create("UIListLayout", { Padding = UDim.new(0, 10), SortOrder = Enum.SortOrder.LayoutOrder }),
		})
	end

	local tab = setmetatable({
		Window = window,
		Name = config.Name or "Tab",
		_button = button,
		_icon = tabIcon,
		_label = nameLabel,
		_page = page,
		_left = column("Left", 0, 0),
		_right = column("Right", 1, 1),
		_count = 0,
	}, Tab)

	table.insert(self.Tabs, tab)

	window._connect(button.MouseButton1Click, function()
		window:SelectTab(tab)
	end)
	window._connect(button.MouseEnter, function()
		if window._activeTab ~= tab then
			tween(button, { BackgroundTransparency = 0.5 })
		end
	end)
	window._connect(button.MouseLeave, function()
		if window._activeTab ~= tab then
			tween(button, { BackgroundTransparency = 1 })
		end
	end)

	if not window._activeTab then
		window:SelectTab(tab)
	end
	return tab
end

function Library:SelectTab(tab)
	local theme = self.Theme
	self._activeTab = tab
	for _, other in ipairs(self.Tabs) do
		local active = other == tab
		other._page.Visible = active
		other._label.Visible = active or other._icon == nil
		other._label.TextColor3 = active and theme.Text or theme.TextDim
		tween(other._button, { BackgroundTransparency = active and 0 or 1 })
		if other._icon then
			local prop = other._icon:IsA("ImageLabel") and "ImageColor3" or "TextColor3"
			tween(other._icon, { [prop] = active and theme.Accent or theme.TextMuted })
		end
	end
end

function Tab:Select()
	self.Window:SelectTab(self)
end

--// sections ----------------------------------------------------------------

local Section = {}
Section.__index = Section

function Tab:CreateSection(config)
	config = config or {}
	local window = self.Window
	local theme = window.Theme
	local columnFrame = (config.Side == "Right") and self._right or self._left
	self._count = self._count + 1

	local frame = create("Frame", {
		Name = config.Name or "Section",
		Parent = columnFrame,
		LayoutOrder = self._count,
		AutomaticSize = Enum.AutomaticSize.Y,
		Size = UDim2.new(1, 0, 0, 0),
		BackgroundColor3 = theme.Section,
		BorderSizePixel = 0,
	}, {
		corner(6),
		stroke(theme.Border),
		padding(10, 10, 12, 10),
		create("UIListLayout", { Padding = UDim.new(0, 10), SortOrder = Enum.SortOrder.LayoutOrder }),
	})

	local header = create("Frame", {
		Name = "Header",
		Parent = frame,
		LayoutOrder = 0,
		Size = UDim2.new(1, 0, 0, 18),
		BackgroundTransparency = 1,
	}, {
		create("UIListLayout", {
			FillDirection = Enum.FillDirection.Horizontal,
			VerticalAlignment = Enum.VerticalAlignment.Center,
			Padding = UDim.new(0, 8),
			SortOrder = Enum.SortOrder.LayoutOrder,
		}),
	})
	local sectionIcon = icon(config.Icon, theme.Accent, 14)
	if sectionIcon then
		sectionIcon.LayoutOrder = 1
		sectionIcon.Parent = header
	end
	create("TextLabel", {
		Name = "Title",
		Parent = header,
		LayoutOrder = 2,
		AutomaticSize = Enum.AutomaticSize.X,
		Size = UDim2.fromOffset(0, 18),
		BackgroundTransparency = 1,
		Font = FONT,
		Text = config.Name or "Section",
		TextSize = 12,
		TextColor3 = theme.Text,
	})

	local body = create("Frame", {
		Name = "Body",
		Parent = frame,
		LayoutOrder = 1,
		AutomaticSize = Enum.AutomaticSize.Y,
		Size = UDim2.new(1, 0, 0, 0),
		BackgroundTransparency = 1,
	}, {
		create("UIListLayout", { Padding = UDim.new(0, 8), SortOrder = Enum.SortOrder.LayoutOrder }),
	})

	return setmetatable({ Window = window, Theme = theme, _body = body, _count = 0 }, Section)
end

function Section:_next()
	self._count = self._count + 1
	return self._count
end

function Section:_setFlag(flag, value)
	if flag then
		self.Window.Flags[flag] = value
	end
end

--// label

function Section:AddLabel(text)
	local theme = self.Theme
	local label = create("TextLabel", {
		Name = "Label",
		Parent = self._body,
		LayoutOrder = self:_next(),
		AutomaticSize = Enum.AutomaticSize.Y,
		Size = UDim2.new(1, 0, 0, 0),
		BackgroundTransparency = 1,
		Font = FONT,
		Text = tostring(text or ""),
		TextSize = 12,
		TextColor3 = theme.TextDim,
		TextWrapped = true,
		TextXAlignment = Enum.TextXAlignment.Left,
	})
	return {
		Instance = label,
		Set = function(_, newText)
			label.Text = tostring(newText)
		end,
	}
end

--// button

function Section:AddButton(config)
	config = config or {}
	local theme = self.Theme
	local window = self.Window

	local button = create("TextButton", {
		Name = config.Name or "Button",
		Parent = self._body,
		LayoutOrder = self:_next(),
		Size = UDim2.new(1, 0, 0, 28),
		BackgroundColor3 = theme.Element,
		AutoButtonColor = false,
		Font = FONT,
		Text = config.Name or "Button",
		TextSize = 12,
		TextColor3 = theme.Text,
	}, { corner(5) })

	window._connect(button.MouseEnter, function()
		tween(button, { BackgroundColor3 = theme.ElementHover })
	end)
	window._connect(button.MouseLeave, function()
		tween(button, { BackgroundColor3 = theme.Element })
	end)
	window._connect(button.MouseButton1Click, function()
		button.BackgroundColor3 = theme.AccentSoft
		tween(button, { BackgroundColor3 = theme.ElementHover }, TweenInfo.new(0.3))
		safeCall(config.Callback)
	end)

	return {
		Instance = button,
		SetText = function(_, text)
			button.Text = tostring(text)
		end,
	}
end

--// toggle

function Section:AddToggle(config)
	config = config or {}
	local theme = self.Theme
	local window = self.Window
	local state = config.Default == true

	local row = create("TextButton", {
		Name = config.Name or "Toggle",
		Parent = self._body,
		LayoutOrder = self:_next(),
		Size = UDim2.new(1, 0, 0, 20),
		BackgroundTransparency = 1,
		AutoButtonColor = false,
		Text = "",
	})

	local label = create("TextLabel", {
		Parent = row,
		Size = UDim2.new(1, -26, 1, 0),
		BackgroundTransparency = 1,
		Font = FONT,
		Text = config.Name or "Toggle",
		TextSize = 12,
		TextColor3 = theme.TextDim,
		TextXAlignment = Enum.TextXAlignment.Left,
		TextTruncate = Enum.TextTruncate.AtEnd,
	})

	local boxStroke = stroke(theme.Border)
	local box = create("Frame", {
		Name = "Box",
		Parent = row,
		AnchorPoint = Vector2.new(1, 0.5),
		Position = UDim2.fromScale(1, 0.5),
		Size = UDim2.fromOffset(16, 16),
		BackgroundColor3 = theme.Element,
		BorderSizePixel = 0,
	}, { corner(3), boxStroke })

	-- check mark drawn from two bars so it needs no font or image
	local check = create("Frame", {
		Name = "Check",
		Parent = box,
		Size = UDim2.fromScale(1, 1),
		BackgroundTransparency = 1,
	})
	local short = create("Frame", {
		Parent = check,
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromOffset(5.5, 9.5),
		Size = UDim2.fromOffset(5, 2),
		Rotation = 45,
		BackgroundColor3 = Color3.new(1, 1, 1),
		BorderSizePixel = 0,
	})
	local long = create("Frame", {
		Parent = check,
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromOffset(9.6, 7.8),
		Size = UDim2.fromOffset(8.5, 2),
		Rotation = -50,
		BackgroundColor3 = Color3.new(1, 1, 1),
		BorderSizePixel = 0,
	})

	local function render(instant)
		local info = instant and TweenInfo.new(0) or FAST
		tween(box, { BackgroundColor3 = state and theme.Accent or theme.Element }, info)
		tween(boxStroke, { Color = state and theme.Accent or theme.Border }, info)
		tween(label, { TextColor3 = state and theme.Text or theme.TextDim }, info)
		tween(short, { BackgroundTransparency = state and 0 or 1 }, info)
		tween(long, { BackgroundTransparency = state and 0 or 1 }, info)
	end

	local toggle = { Instance = row }
	function toggle:Set(value)
		state = value == true
		render(false)
		self._section:_setFlag(config.Flag, state)
		safeCall(config.Callback, state)
	end
	function toggle:Get()
		return state
	end
	toggle._section = self

	self:_setFlag(config.Flag, state)
	render(true)

	window._connect(row.MouseButton1Click, function()
		toggle:Set(not state)
	end)
	window._connect(row.MouseEnter, function()
		if not state then
			tween(label, { TextColor3 = theme.Text:Lerp(theme.TextDim, 0.4) })
		end
	end)
	window._connect(row.MouseLeave, function()
		tween(label, { TextColor3 = state and theme.Text or theme.TextDim })
	end)

	return toggle
end

--// slider

function Section:AddSlider(config)
	config = config or {}
	local theme = self.Theme
	local window = self.Window
	local min = config.Min or 0
	local max = config.Max or 100
	if max <= min then
		max = min + 1
	end
	local increment = config.Increment or 1
	local decimals = decimalsOf(increment)
	local suffix = config.Suffix or ""
	local value = math.clamp(config.Default or min, min, max)

	local holder = create("Frame", {
		Name = config.Name or "Slider",
		Parent = self._body,
		LayoutOrder = self:_next(),
		Size = UDim2.new(1, 0, 0, 40),
		BackgroundTransparency = 1,
	})

	create("TextLabel", {
		Parent = holder,
		Size = UDim2.new(0.65, 0, 0, 16),
		BackgroundTransparency = 1,
		Font = FONT,
		Text = config.Name or "Slider",
		TextSize = 12,
		TextColor3 = theme.Text,
		TextXAlignment = Enum.TextXAlignment.Left,
		TextTruncate = Enum.TextTruncate.AtEnd,
	})

	local valueLabel = create("TextLabel", {
		Parent = holder,
		AnchorPoint = Vector2.new(1, 0),
		Position = UDim2.fromScale(1, 0),
		Size = UDim2.new(0.35, 0, 0, 16),
		BackgroundTransparency = 1,
		Font = FONT,
		Text = "",
		TextSize = 12,
		TextColor3 = theme.Text,
		TextXAlignment = Enum.TextXAlignment.Right,
	})

	local track = create("TextButton", {
		Name = "Track",
		Parent = holder,
		AnchorPoint = Vector2.new(0, 1),
		Position = UDim2.fromScale(0, 1),
		Size = UDim2.new(1, 0, 0, 16),
		BackgroundColor3 = theme.Element,
		AutoButtonColor = false,
		Text = "",
	}, { corner(3) })

	local fill = create("Frame", {
		Name = "Fill",
		Parent = track,
		Size = UDim2.fromScale(0, 1),
		BackgroundColor3 = theme.Accent,
		BackgroundTransparency = 0.15,
		BorderSizePixel = 0,
	}, { corner(3) })

	local trackText = create("TextLabel", {
		Parent = track,
		Size = UDim2.fromScale(1, 1),
		BackgroundTransparency = 1,
		Font = FONT,
		Text = "",
		TextSize = 11,
		TextColor3 = theme.Text,
		ZIndex = 2,
	})

	local function format(v)
		return string.format("%." .. decimals .. "f", v) .. suffix
	end

	local function render(instant)
		local alpha = (value - min) / (max - min)
		tween(fill, { Size = UDim2.fromScale(alpha, 1) }, instant and TweenInfo.new(0) or TweenInfo.new(0.08))
		valueLabel.Text = format(value)
		trackText.Text = format(value)
	end

	local slider = { Instance = holder }
	local section = self
	function slider:Set(newValue, silent)
		newValue = math.clamp(round(tonumber(newValue) or min, increment), min, max)
		if decimals > 0 then
			newValue = tonumber(string.format("%." .. decimals .. "f", newValue))
		end
		local changed = newValue ~= value
		value = newValue
		render(false)
		section:_setFlag(config.Flag, value)
		if changed and not silent then
			safeCall(config.Callback, value)
		end
	end
	function slider:Get()
		return value
	end

	section:_setFlag(config.Flag, value)
	render(true)

	local dragging = false
	local function fromInput(input)
		local x = input.Position.X
		local alpha = math.clamp((x - track.AbsolutePosition.X) / track.AbsoluteSize.X, 0, 1)
		slider:Set(min + (max - min) * alpha)
	end

	window._connect(track.InputBegan, function(input)
		if input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch then
			dragging = true
			fromInput(input)
		end
	end)
	window._connect(UserInputService.InputChanged, function(input)
		if dragging and (input.UserInputType == Enum.UserInputType.MouseMovement or input.UserInputType == Enum.UserInputType.Touch) then
			fromInput(input)
		end
	end)
	window._connect(UserInputService.InputEnded, function(input)
		if input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch then
			dragging = false
		end
	end)
	window._connect(track.MouseEnter, function()
		tween(track, { BackgroundColor3 = theme.ElementHover })
	end)
	window._connect(track.MouseLeave, function()
		tween(track, { BackgroundColor3 = theme.Element })
	end)

	return slider
end

--// dropdown

function Section:AddDropdown(config)
	config = config or {}
	local theme = self.Theme
	local window = self.Window
	local multi = config.Multi == true
	local options = table.clone(config.Options or {})
	local open = false

	-- selected: set of option -> true
	local selected = {}
	if multi then
		for _, v in ipairs(type(config.Default) == "table" and config.Default or {}) do
			selected[v] = true
		end
	elseif config.Default ~= nil then
		selected[config.Default] = true
	end

	local holder = create("Frame", {
		Name = config.Name or "Dropdown",
		Parent = self._body,
		LayoutOrder = self:_next(),
		AutomaticSize = Enum.AutomaticSize.Y,
		Size = UDim2.new(1, 0, 0, 0),
		BackgroundTransparency = 1,
	}, {
		create("UIListLayout", { Padding = UDim.new(0, 5), SortOrder = Enum.SortOrder.LayoutOrder }),
	})

	create("TextLabel", {
		Parent = holder,
		LayoutOrder = 1,
		Size = UDim2.new(1, 0, 0, 16),
		BackgroundTransparency = 1,
		Font = FONT,
		Text = config.Name or "Dropdown",
		TextSize = 12,
		TextColor3 = theme.Text,
		TextXAlignment = Enum.TextXAlignment.Left,
		TextTruncate = Enum.TextTruncate.AtEnd,
	})

	local box = create("TextButton", {
		Name = "Box",
		Parent = holder,
		LayoutOrder = 2,
		Size = UDim2.new(1, 0, 0, 26),
		BackgroundColor3 = theme.Element,
		AutoButtonColor = false,
		Text = "",
	}, { corner(4) })

	local valueLabel = create("TextLabel", {
		Parent = box,
		Position = UDim2.fromOffset(9, 0),
		Size = UDim2.new(1, -36, 1, 0),
		BackgroundTransparency = 1,
		Font = FONT,
		Text = "--",
		TextSize = 12,
		TextColor3 = theme.Text,
		TextXAlignment = Enum.TextXAlignment.Left,
		TextTruncate = Enum.TextTruncate.AtEnd,
	})

	-- 3x2 dot grid icon on the right
	local grid = create("Frame", {
		Name = "Grid",
		Parent = box,
		AnchorPoint = Vector2.new(1, 0.5),
		Position = UDim2.new(1, -9, 0.5, 0),
		Size = UDim2.fromOffset(9, 13),
		BackgroundTransparency = 1,
	})
	for row = 0, 2 do
		for col = 0, 1 do
			create("Frame", {
				Parent = grid,
				Position = UDim2.fromOffset(col * 6, row * 5),
				Size = UDim2.fromOffset(3, 3),
				BackgroundColor3 = theme.Accent,
				BorderSizePixel = 0,
			})
		end
	end

	local list = create("Frame", {
		Name = "List",
		Parent = holder,
		LayoutOrder = 3,
		AutomaticSize = Enum.AutomaticSize.Y,
		Size = UDim2.new(1, 0, 0, 0),
		BackgroundColor3 = theme.Background,
		BorderSizePixel = 0,
		Visible = false,
	}, {
		corner(4),
		stroke(theme.Border),
		padding(4),
		create("UIListLayout", { Padding = UDim.new(0, 2), SortOrder = Enum.SortOrder.LayoutOrder }),
	})

	local optionButtons = {}

	local function values()
		local out = {}
		for _, opt in ipairs(options) do
			if selected[opt] then
				table.insert(out, opt)
			end
		end
		return out
	end

	local function current()
		if multi then
			return values()
		end
		return values()[1]
	end

	local function render()
		local vals = values()
		valueLabel.Text = #vals > 0 and table.concat(vals, ", ") or "--"
		valueLabel.TextColor3 = #vals > 0 and theme.Text or theme.TextDim
		for opt, btn in pairs(optionButtons) do
			local on = selected[opt] == true
			btn.TextColor3 = on and theme.Accent or theme.TextDim
			btn.Marker.BackgroundTransparency = on and 0 or 1
		end
	end

	local dropdown = { Instance = holder }
	local section = self

	local function commit()
		render()
		section:_setFlag(config.Flag, current())
		safeCall(config.Callback, current())
	end

	local function setOpen(state)
		open = state
		list.Visible = open
		tween(box, { BackgroundColor3 = open and theme.ElementHover or theme.Element })
	end

	local function buildOptions()
		for _, btn in pairs(optionButtons) do
			btn:Destroy()
		end
		table.clear(optionButtons)
		for i, opt in ipairs(options) do
			local btn = create("TextButton", {
				Name = tostring(opt),
				Parent = list,
				LayoutOrder = i,
				Size = UDim2.new(1, 0, 0, 22),
				BackgroundColor3 = theme.Element,
				BackgroundTransparency = 1,
				AutoButtonColor = false,
				Font = FONT,
				Text = tostring(opt),
				TextSize = 12,
				TextColor3 = theme.TextDim,
				TextXAlignment = Enum.TextXAlignment.Left,
				TextTruncate = Enum.TextTruncate.AtEnd,
			}, { corner(3), padding(0, 6, 0, 12) })
			create("Frame", {
				Name = "Marker",
				Parent = btn,
				AnchorPoint = Vector2.new(0, 0.5),
				Position = UDim2.new(0, -7, 0.5, 0),
				Size = UDim2.fromOffset(2, 12),
				BackgroundColor3 = theme.Accent,
				BackgroundTransparency = 1,
				BorderSizePixel = 0,
			})
			optionButtons[opt] = btn

			btn.MouseEnter:Connect(function()
				tween(btn, { BackgroundTransparency = 0 })
			end)
			btn.MouseLeave:Connect(function()
				tween(btn, { BackgroundTransparency = 1 })
			end)
			btn.MouseButton1Click:Connect(function()
				if multi then
					selected[opt] = not selected[opt] or nil
				else
					table.clear(selected)
					selected[opt] = true
					setOpen(false)
				end
				commit()
			end)
		end
		render()
	end

	function dropdown:Set(value)
		table.clear(selected)
		if multi then
			for _, v in ipairs(type(value) == "table" and value or { value }) do
				selected[v] = true
			end
		elseif value ~= nil then
			selected[value] = true
		end
		commit()
	end
	function dropdown:Get()
		return current()
	end
	function dropdown:Refresh(newOptions, keepSelection)
		options = table.clone(newOptions or {})
		if not keepSelection then
			table.clear(selected)
		end
		buildOptions()
		section:_setFlag(config.Flag, current())
	end

	window._connect(box.MouseButton1Click, function()
		setOpen(not open)
	end)
	window._connect(box.MouseEnter, function()
		if not open then
			tween(box, { BackgroundColor3 = theme.ElementHover })
		end
	end)
	window._connect(box.MouseLeave, function()
		if not open then
			tween(box, { BackgroundColor3 = theme.Element })
		end
	end)

	buildOptions()
	section:_setFlag(config.Flag, current())
	return dropdown
end

return Library
