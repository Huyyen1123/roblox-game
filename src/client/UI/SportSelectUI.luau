--[[
	SportSelectUI
	Full-screen discipline picker. Opens automatically until the player has a sport, and can be
	reopened from the HUD. The client only *requests* a sport; the server validates it and sets
	the player's Sport attribute, which is what actually closes this screen.
]]

local GuiService = game:GetService("GuiService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local UserInputService = game:GetService("UserInputService")

local Constants = require(ReplicatedStorage.Shared.Constants)
local SportConfig = require(ReplicatedStorage.Shared.Config.SportConfig)
local Create = require(ReplicatedStorage.Shared.Util.Create)

local Remotes = ReplicatedStorage:WaitForChild("Remotes")
local player = Players.LocalPlayer

local SportSelectUI = {}

local screen: ScreenGui
local cards: { [string]: TextButton } = {}
local pending = false
local stanceButton: TextButton

local STANCE_LABELS = {
	Regular = "SNOWBOARD STANCE:  REGULAR  (left foot forward)",
	Goofy = "SNOWBOARD STANCE:  GOOFY  (right foot forward)",
}

local function refreshStance()
	stanceButton.Text = STANCE_LABELS[player:GetAttribute("Stance") or "Regular"]
end

local function corner(radius: number)
	return Create("UICorner", { CornerRadius = UDim.new(0, radius) })
end

local function text(properties, maxTextSize: number?)
	properties.BackgroundTransparency = 1
	properties.Font = properties.Font or Enum.Font.GothamBold
	properties.TextColor3 = properties.TextColor3 or Color3.new(1, 1, 1)
	properties.TextScaled = true
	return Create("TextLabel", properties, {
		Create("UITextSizeConstraint", { MaxTextSize = maxTextSize or 48 }),
	})
end

local function buildCard(sportId: string, order: number): TextButton
	local sport = SportConfig.Sports[sportId]
	local card = Create("TextButton", {
		Name = sportId,
		LayoutOrder = order,
		Size = UDim2.fromScale(0.42, 1),
		BackgroundColor3 = Color3.fromRGB(22, 30, 44),
		AutoButtonColor = true,
		Text = "",
		Selectable = true,
	}, {
		corner(14),
		Create("UIStroke", { Name = "Stroke", Color = sport.AccentColor, Thickness = 2, Transparency = 0.4 }),
		Create("Frame", {
			Name = "Accent",
			Size = UDim2.new(1, 0, 0, 8),
			BackgroundColor3 = sport.AccentColor,
			BorderSizePixel = 0,
		}, { corner(14) }),
		text({
			Name = "Title",
			Text = sport.DisplayName:upper(),
			Font = Enum.Font.GothamBlack,
			Position = UDim2.fromScale(0.08, 0.12),
			Size = UDim2.fromScale(0.84, 0.2),
			TextXAlignment = Enum.TextXAlignment.Left,
		}, 30),
		text({
			Name = "Tagline",
			Text = sport.Tagline,
			TextColor3 = sport.AccentColor,
			Position = UDim2.fromScale(0.08, 0.34),
			Size = UDim2.fromScale(0.84, 0.1),
			TextXAlignment = Enum.TextXAlignment.Left,
		}),
		text({
			Name = "Description",
			Text = sport.Description,
			Font = Enum.Font.Gotham,
			TextColor3 = Color3.fromRGB(190, 200, 215),
			TextWrapped = true,
			Position = UDim2.fromScale(0.08, 0.5),
			Size = UDim2.fromScale(0.84, 0.3),
			TextXAlignment = Enum.TextXAlignment.Left,
			TextYAlignment = Enum.TextYAlignment.Top,
		}),
		text({
			Name = "Current",
			Text = "CURRENT",
			TextColor3 = sport.AccentColor,
			Position = UDim2.fromScale(0.08, 0.84),
			Size = UDim2.fromScale(0.84, 0.09),
			TextXAlignment = Enum.TextXAlignment.Left,
			Visible = false,
		}),
	})

	card.Activated:Connect(function()
		if pending then
			return
		end
		if player:GetAttribute(Constants.Attributes.Sport) == sportId then
			SportSelectUI.Close()
			return
		end
		pending = true
		Remotes.SelectSport:FireServer(sportId)
		-- Unblock if the server rejected the request (e.g. during a race).
		task.delay(2, function()
			pending = false
		end)
	end)

	return card
end

local function refreshCurrent()
	local current = player:GetAttribute(Constants.Attributes.Sport)
	for sportId, card in cards do
		card.Current.Visible = sportId == current
		card.Stroke.Transparency = if sportId == current then 0 else 0.4
	end
end

local function build()
	screen = Create("ScreenGui", {
		Name = "SportSelect",
		ResetOnSpawn = false,
		IgnoreGuiInset = true,
		DisplayOrder = 10,
		Enabled = false,
		ZIndexBehavior = Enum.ZIndexBehavior.Sibling,
	})

	local backdrop = Create("Frame", {
		Name = "Backdrop",
		Size = UDim2.fromScale(1, 1),
		BackgroundColor3 = Color3.fromRGB(8, 14, 24),
		BackgroundTransparency = 0.25,
		Parent = screen,
	})

	local panel = Create("Frame", {
		Name = "Panel",
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.5),
		Size = UDim2.fromScale(0.8, 0.7),
		BackgroundTransparency = 1,
		Parent = backdrop,
	}, {
		Create("UISizeConstraint", { MaxSize = Vector2.new(900, 560) }),
	})

	text({
		Name = "Title",
		Text = "PROJECT DOWNHILL",
		Font = Enum.Font.GothamBlack,
		Size = UDim2.fromScale(1, 0.14),
		Parent = panel,
	})
	text({
		Name = "Subtitle",
		Text = "Choose your discipline. Same speed, same potential, different style.",
		Font = Enum.Font.Gotham,
		TextColor3 = Color3.fromRGB(180, 195, 215),
		Position = UDim2.fromScale(0, 0.15),
		Size = UDim2.fromScale(1, 0.07),
		Parent = panel,
	})

	local row = Create("Frame", {
		Name = "Cards",
		Position = UDim2.fromScale(0, 0.28),
		Size = UDim2.fromScale(1, 0.62),
		BackgroundTransparency = 1,
		Parent = panel,
	}, {
		Create("UIListLayout", {
			FillDirection = Enum.FillDirection.Horizontal,
			HorizontalAlignment = Enum.HorizontalAlignment.Center,
			Padding = UDim.new(0.04, 0),
			SortOrder = Enum.SortOrder.LayoutOrder,
		}),
	})

	for order, sportId in SportConfig.Order do
		local card = buildCard(sportId, order)
		card.Parent = row
		cards[sportId] = card
	end

	-- Regular / goofy toggle (which foot leads on the snowboard)
	stanceButton = Create("TextButton", {
		Name = "Stance",
		AnchorPoint = Vector2.new(0.5, 0),
		Position = UDim2.fromScale(0.5, 0.93),
		Size = UDim2.new(0, 380, 0.07, 0),
		BackgroundColor3 = Color3.fromRGB(22, 30, 44),
		Font = Enum.Font.GothamBold,
		TextColor3 = Color3.fromRGB(200, 215, 235),
		TextSize = 14,
		Text = "",
		Parent = panel,
	}, { corner(8) })
	stanceButton.Activated:Connect(function()
		local next = if player:GetAttribute("Stance") == "Goofy" then "Regular" else "Goofy"
		Remotes.SelectStance:FireServer(next)
	end)
	refreshStance()

	screen.Parent = player:WaitForChild("PlayerGui")
end

function SportSelectUI.Open()
	if player:GetAttribute(Constants.Attributes.InRace) then
		return
	end
	refreshCurrent()
	screen.Enabled = true
	if UserInputService.GamepadEnabled then
		GuiService.SelectedObject = cards[SportConfig.Order[1]]
	end
end

function SportSelectUI.Close()
	screen.Enabled = false
	if GuiService.SelectedObject and GuiService.SelectedObject:IsDescendantOf(screen) then
		GuiService.SelectedObject = nil
	end
end

function SportSelectUI.IsOpen(): boolean
	return screen.Enabled
end

function SportSelectUI.Start()
	build()

	player:GetAttributeChangedSignal("Stance"):Connect(refreshStance)
	player:GetAttributeChangedSignal(Constants.Attributes.Sport):Connect(function()
		pending = false
		refreshCurrent()
		if player:GetAttribute(Constants.Attributes.Sport) then
			SportSelectUI.Close()
		end
	end)

	if not player:GetAttribute(Constants.Attributes.Sport) then
		SportSelectUI.Open()
	end
end

return SportSelectUI
