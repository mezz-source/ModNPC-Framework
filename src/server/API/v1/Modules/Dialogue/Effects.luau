--[[
	How a typed letter looks at a moment in time, as an offset from where Layout put it and an opacity. Every result is a
	formula of the time and the glyph alone: nothing is stored between frames, so a late or skipped frame just shows the
	letter where it should be by then, and the same time always looks the same.

	Sizes are fractions of the TextSize the layout was measured at, so they keep their look on any board. Offsets are in
	Layout pixels (Board.ScaleOffset turns them into scale) and add up, so <shake><wave> does both. Effects never move the
	layout, so a shaking word can't push its neighbors or change where lines wrap.
]]

local TypeDialogue = require(script.Parent.TypeDialogue)

type Glyph = TypeDialogue.Glyph

local EffectNames = TypeDialogue.Effects

local Effects = {}

-- Seconds a new letter takes to fade in
local FADE_IN = 0.08
-- How far a new letter starts below its spot and slides up while it fades in
local RISE = 0.12

-- Shake distance at intensity 1
local SHAKE_SIZE = 0.05
-- How many times a second shake picks a new offset, whatever the frame rate
local SHAKE_RATE = 24

-- Wave height at intensity 1
local WAVE_SIZE = 0.1
-- Bobs a second
local WAVE_HZ = 1.2
-- Radians each letter lags the one before it, which makes the wave travel along the text
local WAVE_PHASE = 0.6

Effects.FadeInTime = FADE_IN

-- A hash, not a random number: the same inputs always give the same value in [-1, 1)
local function noise(index: number, frame: number, axis: number): number
	local value = math.sin(index * 12.9898 + frame * 78.233 + axis * 37.719) * 43758.5453
	return (value - math.floor(value)) * 2 - 1
end

-- The fade in of a letter typed `age` seconds ago: its opacity and how far below its spot it is
function Effects.reveal(age: number, textSize: number): (number, number)
	local fade = math.clamp(age / FADE_IN, 0, 1)
	return fade, (1 - fade) * RISE * textSize
end

-- The offset of a glyph's effects at `time` seconds into the line
function Effects.offset(glyph: Glyph, time: number, textSize: number): (number, number)
	local active = glyph.Style.Effects
	local dx, dy = 0, 0

	local shake = active[EffectNames.Shake]
	if shake then
		local frame = math.floor(time * SHAKE_RATE)
		local size = SHAKE_SIZE * textSize * shake
		dx += noise(glyph.Index, frame, 0) * size
		dy += noise(glyph.Index, frame, 1) * size
	end

	local wave = active[EffectNames.Wave]
	if wave then
		dy -= math.sin(time * WAVE_HZ * 2 * math.pi - glyph.Index * WAVE_PHASE) * WAVE_SIZE * textSize * wave
	end

	return dx, dy
end

return Effects
