local TweenService = game:GetService("TweenService")
local ServerScriptService = game:GetService("ServerScriptService")
local TypeBars = require(ServerScriptService.ModNPCServer.Types.v1.TypeBars)
local BarClass = {}

type Bar = TypeBars.Bar
type BarOptions = TypeBars.BarOptions

-- The first change holds the change fill for CHANGE_HOLD_BASE seconds, and every further change before it catches up
-- pushes the catch-up back by CHANGE_HOLD_EXTENSION, so a stream of small hits shows as one trail that closes when the
-- hits stop. The hold never runs further than CHANGE_HOLD_MAX past the latest change.
local CHANGE_HOLD_BASE = 0.4
local CHANGE_HOLD_EXTENSION = 0.15
local CHANGE_HOLD_MAX = 1.5
local CATCH_UP_TWEEN = TweenInfo.new(0.35, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)
-- How the fill (and the change fill, when it moves with the fill) travels to a new percentage
local FILL_TWEEN = TweenInfo.new(0.2, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)

-- One full flash (fill color to the flash color and back) takes FLASH_DEFAULT_PERIOD seconds unless the caller says otherwise
local FLASH_DEFAULT_PERIOD = 0.5

local function fractionSize(fraction: number): UDim2
	return UDim2.fromScale(fraction, 1)
end

local function isFraction(value: any): boolean
	return typeof(value) == "number" and value == value
end

-- A bar's size is its height as a fraction of the gui's height
function BarClass.isValidSize(value: any): boolean
	return typeof(value) == "number" and value > 0 and value <= 1
end

function BarClass.isValidLayoutOrder(value: any): boolean
	return typeof(value) == "number" and value % 1 == 0
end

local function getFrame(parent: Instance, name: string): Frame?
	local child = parent:FindFirstChild(name)
	if child and child:IsA("Frame") then
		return child
	end

	return nil
end

-- Whether the frame has the pieces of a bar, and the reason when it does not
function BarClass.validateFrame(frame: Instance): string?
	if not frame:IsA("Frame") then
		return "bar is not a Frame"
	end

	local mainBar = getFrame(frame, "MainBar")
	if not mainBar then
		return "bar has no MainBar frame"
	end

	for _, name in { "Fill", "ChangeFill", "SecondaryFill" } do
		if not getFrame(mainBar, name) then
			return "bar's MainBar has no " .. name .. " frame"
		end
	end

	return nil
end

-- Wraps a bar frame (validated with validateFrame) in the bar. onDestroyed runs once when the bar goes away, however
-- that happens: Destroy, or the frame being destroyed or removed from its parent (which includes the character going).
function BarClass.new(frame: Frame, name: string, options: BarOptions, onDestroyed: () -> ()): Bar
	local mainBar = frame:FindFirstChild("MainBar") :: Frame
	local fill = mainBar:FindFirstChild("Fill") :: Frame
	local changeFill = mainBar:FindFirstChild("ChangeFill") :: Frame
	local secondaryFill = mainBar:FindFirstChild("SecondaryFill") :: Frame

	local destroyed = false
	local fillFraction = math.clamp(options.Fill or 1, 0, 1)
	local secondaryFraction = math.clamp(options.SecondaryFill or 0, 0, 1)
	-- the template's own height and order unless the options say otherwise
	local size = options.Size or frame.Size.Y.Scale
	local layoutOrder = options.LayoutOrder or frame.LayoutOrder

	-- the catch-up of the change fill: the thread waiting out the hold, the time it is held until, and the tween
	local catchUpThread: thread? = nil
	local holdUntil = 0
	-- (a gain tweens the change fill along with the fill in the same slot, so a following change cuts either short)
	local catchUpTween: Tween? = nil
	local fillTween: Tween? = nil
	local connections: { RBXScriptConnection } = {}

	-- the fill flash: the color the fill returns to, the flash color and period, and the looping tween. flashBaseColor is
	-- only meaningful while a flash is running.
	local flashTween: Tween? = nil
	local flashBaseColor = Color3.new()
	local flashColor = Color3.new()
	local flashPeriod = FLASH_DEFAULT_PERIOD

	local function playFlash()
		if flashTween then
			flashTween:Cancel()
		end

		fill.BackgroundColor3 = flashBaseColor
		local info = TweenInfo.new(flashPeriod / 2, Enum.EasingStyle.Sine, Enum.EasingDirection.InOut, -1, true)
		local tween = TweenService:Create(fill, info, { BackgroundColor3 = flashColor })
		flashTween = tween
		tween:Play()
	end

	local function stopFlash()
		if not flashTween then
			return
		end

		flashTween:Cancel()
		flashTween = nil
		fill.BackgroundColor3 = flashBaseColor
	end

	local function cancelFillTween()
		if fillTween then
			fillTween:Cancel()
			fillTween = nil
		end
	end

	local function cancelCatchUp()
		if catchUpThread then
			task.cancel(catchUpThread)
			catchUpThread = nil
		end

		if catchUpTween then
			catchUpTween:Cancel()
			catchUpTween = nil
		end
	end

	local function startCatchUp()
		if catchUpThread then
			return
		end

		catchUpThread = task.spawn(function()
			while true do
				local remaining = holdUntil - os.clock()
				if remaining <= 0 then
					break
				end
				task.wait(remaining)
			end

			catchUpThread = nil
			local tween = TweenService:Create(changeFill, CATCH_UP_TWEEN, { Size = fractionSize(fillFraction) })
			catchUpTween = tween
			tween.Completed:Once(function()
				if catchUpTween == tween then
					catchUpTween = nil
				end
			end)
			tween:Play()
		end)
	end

	-- Extends the hold while changes keep coming. The extension is relative to the hold already in place, so changes
	-- that land during the hold stack their delay instead of restarting it.
	local function holdChangeFill()
		local now = os.clock()
		if catchUpThread then
			holdUntil = math.min(holdUntil + CHANGE_HOLD_EXTENSION, now + CHANGE_HOLD_MAX)
		else
			-- a catch-up tween still running is cut short where it is; the new change starts a fresh hold from there
			if catchUpTween then
				catchUpTween:Cancel()
				catchUpTween = nil
			end
			holdUntil = now + CHANGE_HOLD_BASE
		end

		startCatchUp()
	end

	local function destroy()
		if destroyed then
			return
		end
		destroyed = true

		cancelCatchUp()
		cancelFillTween()
		if flashTween then
			flashTween:Cancel()
			flashTween = nil
		end
		for _, connection in connections do
			connection:Disconnect()
		end
		table.clear(connections)

		frame:Destroy()
		onDestroyed()
	end

	local bar: Bar = {
		Name = name,

		SetFill = function(_self: Bar, fraction: number)
			if destroyed then
				return
			end
			if not isFraction(fraction) then
				warn("Bar", name, "ignoring invalid fill:", fraction)
				return
			end

			fillFraction = math.clamp(fraction, 0, 1)

			cancelFillTween()
			local newFillTween = TweenService:Create(fill, FILL_TWEEN, { Size = fractionSize(fillFraction) })
			fillTween = newFillTween
			newFillTween:Play()

			if fillFraction >= changeFill.Size.X.Scale then
				-- gained ground: there is nothing to trail behind, so the change fill just stays level with the fill
				cancelCatchUp()
				local newChangeTween = TweenService:Create(changeFill, FILL_TWEEN, { Size = fractionSize(fillFraction) })
				catchUpTween = newChangeTween
				newChangeTween.Completed:Once(function()
					if catchUpTween == newChangeTween then
						catchUpTween = nil
					end
				end)
				newChangeTween:Play()
			else
				holdChangeFill()
			end
		end,

		SetSecondaryFill = function(_self: Bar, fraction: number)
			if destroyed then
				return
			end
			if not isFraction(fraction) then
				warn("Bar", name, "ignoring invalid secondary fill:", fraction)
				return
			end

			secondaryFraction = math.clamp(fraction, 0, 1)
			secondaryFill.Size = fractionSize(secondaryFraction)
		end,

		GetFill = function(_self: Bar): number
			return fillFraction
		end,

		GetSecondaryFill = function(_self: Bar): number
			return secondaryFraction
		end,

		SetFillColor = function(_self: Bar, color: Color3)
			if destroyed or typeof(color) ~= "Color3" then
				return
			end

			if flashTween then
				-- a flash in progress returns to the new color, so the flash is restarted from it
				flashBaseColor = color
				playFlash()
			else
				fill.BackgroundColor3 = color
			end
		end,

		StartFillFlash = function(_self: Bar, color: Color3, period: number?)
			if destroyed then
				return
			end
			if typeof(color) ~= "Color3" then
				warn("Bar", name, "ignoring fill flash with invalid color:", color)
				return
			end
			if period ~= nil and not (typeof(period) == "number" and period > 0 and period < math.huge) then
				warn("Bar", name, "ignoring fill flash with invalid period (must be above 0):", period)
				return
			end

			-- restarting a running flash keeps the original color, not whatever the flash had reached
			if not flashTween then
				flashBaseColor = fill.BackgroundColor3
			end
			flashColor = color
			flashPeriod = period or FLASH_DEFAULT_PERIOD
			playFlash()
		end,

		StopFillFlash = function(_self: Bar)
			if not destroyed then
				stopFlash()
			end
		end,

		IsFillFlashing = function(_self: Bar): boolean
			return flashTween ~= nil
		end,

		SetSecondaryFillColor = function(_self: Bar, color: Color3)
			if not destroyed and typeof(color) == "Color3" then
				secondaryFill.BackgroundColor3 = color
			end
		end,

		SetChangeFillColor = function(_self: Bar, color: Color3)
			if not destroyed and typeof(color) == "Color3" then
				changeFill.BackgroundColor3 = color
			end
		end,

		SetSize = function(_self: Bar, height: number)
			if destroyed then
				return
			end
			if not BarClass.isValidSize(height) then
				warn("Bar", name, "ignoring invalid size (must be above 0 and at most 1):", height)
				return
			end

			size = height
			frame.Size = UDim2.new(frame.Size.X, UDim.new(size, 0))
		end,

		GetSize = function(_self: Bar): number
			return size
		end,

		SetLayoutOrder = function(_self: Bar, order: number)
			if destroyed then
				return
			end
			if not BarClass.isValidLayoutOrder(order) then
				warn("Bar", name, "ignoring invalid layout order (must be an integer):", order)
				return
			end

			layoutOrder = order
			frame.LayoutOrder = order
		end,

		GetLayoutOrder = function(_self: Bar): number
			return layoutOrder
		end,

		IsDestroyed = function(_self: Bar): boolean
			return destroyed
		end,

		Destroy = function(_self: Bar)
			destroy()
		end,
	}

	-- the frame being destroyed (it, its gui or its character) or taken out of its parent ends the bar
	table.insert(connections, frame.Destroying:Connect(destroy))
	table.insert(
		connections,
		frame.AncestryChanged:Connect(function(_, parent)
			if parent == nil then
				destroy()
			end
		end)
	)

	frame.Size = UDim2.new(frame.Size.X, UDim.new(size, 0))
	frame.LayoutOrder = layoutOrder
	fill.Size = fractionSize(fillFraction)
	changeFill.Size = fractionSize(fillFraction)
	secondaryFill.Size = fractionSize(secondaryFraction)
	if options.FillColor then
		fill.BackgroundColor3 = options.FillColor
	end
	if options.SecondaryFillColor then
		secondaryFill.BackgroundColor3 = options.SecondaryFillColor
	end
	if options.ChangeFillColor then
		changeFill.BackgroundColor3 = options.ChangeFillColor
	end

	return bar
end

return BarClass
