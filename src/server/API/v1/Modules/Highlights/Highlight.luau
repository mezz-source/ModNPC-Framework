local TweenService = game:GetService("TweenService")
local ServerScriptService = game:GetService("ServerScriptService")
local TypeHighlights = require(ServerScriptService.ModNPCServer.Types.v1.TypeHighlights)
local HighlightClass = {}

type HighlightObject = TypeHighlights.Highlight
type HighlightOptions = TypeHighlights.HighlightOptions
type HighlightTween = TypeHighlights.HighlightTween

-- How a tween given only as seconds eases
local DEFAULT_EASING_STYLE = Enum.EasingStyle.Quad
local DEFAULT_EASING_DIRECTION = Enum.EasingDirection.Out

-- One full flash (the color to the flash color and back) takes FLASH_DEFAULT_PERIOD seconds unless the caller says otherwise
local FLASH_DEFAULT_PERIOD = 0.5

function HighlightClass.isValidTransparency(value: any): boolean
	return typeof(value) == "number" and value >= 0 and value <= 1
end

-- A finite, non-negative number of seconds
function HighlightClass.isValidDuration(value: any): boolean
	return typeof(value) == "number" and value >= 0 and value < math.huge
end

local function isValidTween(value: any): boolean
	return typeof(value) == "TweenInfo" or HighlightClass.isValidDuration(value)
end

local function isValidPeriod(value: any): boolean
	return typeof(value) == "number" and value > 0 and value < math.huge
end

-- The TweenInfo for a tween argument, nil when it should be set at once
local function toTweenInfo(tween: HighlightTween): TweenInfo?
	if typeof(tween) == "TweenInfo" then
		return tween
	end

	if tween <= 0 then
		return nil
	end

	return TweenInfo.new(tween, DEFAULT_EASING_STYLE, DEFAULT_EASING_DIRECTION)
end

-- Wraps a Highlight instance in the highlight. onDestroyed runs once when the highlight goes away, however that happens:
-- Destroy, or the instance being destroyed or removed from its parent (which includes the character going).
function HighlightClass.new(
	instance: Highlight,
	name: string,
	options: HighlightOptions,
	onDestroyed: () -> ()
): HighlightObject
	local highlight = instance :: any

	local destroyed = false
	local connections: { RBXScriptConnection } = {}

	-- Each property tweens on its own, so tweening the fill never cuts the outline short. `value` is what the property rests
	-- at (or is tweening to); colors can also flash, `flash` being the looping tween that a stop returns to `value` from.
	type Channel = {
		property: string,
		value: any,
		tween: Tween?,
		flash: Tween?,
	}

	local function newChannel(property: string, initial: any): Channel
		return { property = property, value = initial, tween = nil, flash = nil }
	end

	local fillColor = newChannel("FillColor", options.FillColor or highlight.FillColor)
	local outlineColor = newChannel("OutlineColor", options.OutlineColor or highlight.OutlineColor)
	local fillTransparency =
		newChannel("FillTransparency", options.FillTransparency or highlight.FillTransparency)
	local outlineTransparency =
		newChannel("OutlineTransparency", options.OutlineTransparency or highlight.OutlineTransparency)
	local flashPeriod = FLASH_DEFAULT_PERIOD

	local function cancelTween(channel: Channel)
		if channel.tween then
			channel.tween:Cancel()
			channel.tween = nil
		end
	end

	-- Stops a color's flash and puts it back at its resting color
	local function stopChannelFlash(channel: Channel)
		if not channel.flash then
			return
		end

		channel.flash:Cancel()
		channel.flash = nil
		highlight[channel.property] = channel.value
	end

	local function playChannelFlash(channel: Channel, color: Color3)
		cancelTween(channel)
		if channel.flash then
			channel.flash:Cancel()
		end

		highlight[channel.property] = channel.value
		local info = TweenInfo.new(flashPeriod / 2, Enum.EasingStyle.Sine, Enum.EasingDirection.InOut, -1, true)
		local tween = TweenService:Create(highlight, info, { [channel.property] = color })
		channel.flash = tween
		tween:Play()
	end

	-- The color each flashing channel flashes to, so a set during a flash can restart it from the new color
	local flashColors: { [Channel]: Color3 } = {}

	local function setValue(channel: Channel, value: any)
		cancelTween(channel)
		channel.value = value
		local flashColor = flashColors[channel]
		if channel.flash and flashColor then
			-- a flash in progress returns to the new color, so the flash is restarted from it
			playChannelFlash(channel, flashColor)
		else
			highlight[channel.property] = value
		end
	end

	local function tweenValue(channel: Channel, value: any, tween: HighlightTween)
		stopChannelFlash(channel)
		flashColors[channel] = nil
		cancelTween(channel)
		channel.value = value

		local info = toTweenInfo(tween)
		if not info then
			highlight[channel.property] = value
			return
		end

		local newTween = TweenService:Create(highlight, info, { [channel.property] = value })
		channel.tween = newTween
		newTween.Completed:Once(function()
			if channel.tween == newTween then
				channel.tween = nil
			end
		end)
		newTween:Play()
	end

	local function destroy()
		if destroyed then
			return
		end
		destroyed = true

		for _, channel in { fillColor, outlineColor, fillTransparency, outlineTransparency } do
			cancelTween(channel)
			if channel.flash then
				channel.flash:Cancel()
				channel.flash = nil
			end
		end
		for _, connection in connections do
			connection:Disconnect()
		end
		table.clear(connections)

		instance:Destroy()
		onDestroyed()
	end

	local function setColor(channel: Channel, label: string, color: Color3)
		if destroyed then
			return
		end
		if typeof(color) ~= "Color3" then
			warn("Highlight", name, "ignoring invalid " .. label .. ":", color)
			return
		end

		setValue(channel, color)
	end

	local function setTransparency(channel: Channel, label: string, transparency: number)
		if destroyed then
			return
		end
		if not HighlightClass.isValidTransparency(transparency) then
			warn("Highlight", name, "ignoring invalid " .. label .. " (must be 0 to 1):", transparency)
			return
		end

		setValue(channel, transparency)
	end

	local function tweenColor(channel: Channel, label: string, color: Color3, tween: HighlightTween)
		if destroyed then
			return
		end
		if typeof(color) ~= "Color3" then
			warn("Highlight", name, "ignoring " .. label .. " tween with invalid color:", color)
			return
		end
		if not isValidTween(tween) then
			warn("Highlight", name, "ignoring " .. label .. " tween with invalid tween (seconds or TweenInfo):", tween)
			return
		end

		tweenValue(channel, color, tween)
	end

	local function tweenTransparency(channel: Channel, label: string, transparency: number, tween: HighlightTween)
		if destroyed then
			return
		end
		if not HighlightClass.isValidTransparency(transparency) then
			warn("Highlight", name, "ignoring " .. label .. " tween with invalid transparency (must be 0 to 1):", transparency)
			return
		end
		if not isValidTween(tween) then
			warn("Highlight", name, "ignoring " .. label .. " tween with invalid tween (seconds or TweenInfo):", tween)
			return
		end

		tweenValue(channel, transparency, tween)
	end

	local function stopFlash()
		stopChannelFlash(fillColor)
		stopChannelFlash(outlineColor)
		table.clear(flashColors)
	end

	local object: HighlightObject = {
		Name = name,

		SetFillColor = function(_self: HighlightObject, color: Color3)
			setColor(fillColor, "fill color", color)
		end,

		SetOutlineColor = function(_self: HighlightObject, color: Color3)
			setColor(outlineColor, "outline color", color)
		end,

		SetFillTransparency = function(_self: HighlightObject, transparency: number)
			setTransparency(fillTransparency, "fill transparency", transparency)
		end,

		SetOutlineTransparency = function(_self: HighlightObject, transparency: number)
			setTransparency(outlineTransparency, "outline transparency", transparency)
		end,

		TweenFillColor = function(_self: HighlightObject, color: Color3, tween: HighlightTween)
			tweenColor(fillColor, "fill color", color, tween)
		end,

		TweenOutlineColor = function(_self: HighlightObject, color: Color3, tween: HighlightTween)
			tweenColor(outlineColor, "outline color", color, tween)
		end,

		TweenFillTransparency = function(_self: HighlightObject, transparency: number, tween: HighlightTween)
			tweenTransparency(fillTransparency, "fill transparency", transparency, tween)
		end,

		TweenOutlineTransparency = function(_self: HighlightObject, transparency: number, tween: HighlightTween)
			tweenTransparency(outlineTransparency, "outline transparency", transparency, tween)
		end,

		GetFillColor = function(_self: HighlightObject): Color3
			return fillColor.value
		end,

		GetOutlineColor = function(_self: HighlightObject): Color3
			return outlineColor.value
		end,

		GetFillTransparency = function(_self: HighlightObject): number
			return fillTransparency.value
		end,

		GetOutlineTransparency = function(_self: HighlightObject): number
			return outlineTransparency.value
		end,

		StartFlash = function(_self: HighlightObject, newFillColor: Color3?, newOutlineColor: Color3?, period: number?)
			if destroyed then
				return
			end
			if newFillColor ~= nil and typeof(newFillColor) ~= "Color3" then
				warn("Highlight", name, "ignoring flash with invalid fill color:", newFillColor)
				return
			end
			if newOutlineColor ~= nil and typeof(newOutlineColor) ~= "Color3" then
				warn("Highlight", name, "ignoring flash with invalid outline color:", newOutlineColor)
				return
			end
			if newFillColor == nil and newOutlineColor == nil then
				warn("Highlight", name, "ignoring flash with neither a fill nor an outline color")
				return
			end
			if period ~= nil and not isValidPeriod(period) then
				warn("Highlight", name, "ignoring flash with invalid period (must be above 0):", period)
				return
			end

			flashPeriod = period or FLASH_DEFAULT_PERIOD
			-- channel.value is the resting color, so restarting a running flash keeps the original rather than whatever
			-- the flash had reached
			for _, pair in { { fillColor, newFillColor }, { outlineColor, newOutlineColor } } do
				local channel: Channel, color: Color3? = pair[1], pair[2]
				if color then
					flashColors[channel] = color
					playChannelFlash(channel, color)
				else
					flashColors[channel] = nil
					stopChannelFlash(channel)
				end
			end
		end,

		StopFlash = function(_self: HighlightObject)
			if not destroyed then
				stopFlash()
			end
		end,

		IsFlashing = function(_self: HighlightObject): boolean
			return fillColor.flash ~= nil or outlineColor.flash ~= nil
		end,

		SetEnabled = function(_self: HighlightObject, enabled: boolean)
			if destroyed then
				return
			end
			if typeof(enabled) ~= "boolean" then
				warn("Highlight", name, "ignoring invalid enabled:", enabled)
				return
			end

			instance.Enabled = enabled
		end,

		IsEnabled = function(_self: HighlightObject): boolean
			return not destroyed and instance.Enabled
		end,

		IsDestroyed = function(_self: HighlightObject): boolean
			return destroyed
		end,

		Destroy = function(_self: HighlightObject)
			destroy()
		end,
	}

	highlight.DepthMode = Enum.HighlightDepthMode.Occluded
	highlight.FillColor = fillColor.value
	highlight.OutlineColor = outlineColor.value
	highlight.FillTransparency = fillTransparency.value
	highlight.OutlineTransparency = outlineTransparency.value
	if options.Enabled ~= nil then
		highlight.Enabled = options.Enabled
	end

	-- the depth mode is not the caller's to change: anything that changes it is put back
	table.insert(
		connections,
		instance:GetPropertyChangedSignal("DepthMode"):Connect(function()
			if highlight.DepthMode ~= Enum.HighlightDepthMode.Occluded then
				highlight.DepthMode = Enum.HighlightDepthMode.Occluded
			end
		end)
	)
	-- the instance being destroyed (it, its folder or its character) or taken out of its parent ends the highlight
	table.insert(connections, instance.Destroying:Connect(destroy))
	table.insert(
		connections,
		instance.AncestryChanged:Connect(function(_, parent)
			if parent == nil then
				destroy()
			end
		end)
	)

	return object
end

return HighlightClass
