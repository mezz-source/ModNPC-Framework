-- Dialogue text: Markup parses a line, Layout places its glyphs, Timeline times them, Board puts them on a DialogueUI
-- and Presenter types them out with Effects. None need the API yet
local Dialogue = {}

Dialogue.Markup = require(script.Markup)
Dialogue.Layout = require(script.Layout)
Dialogue.Timeline = require(script.Timeline)
Dialogue.Effects = require(script.Effects)
Dialogue.Board = require(script.Board)
Dialogue.Presenter = require(script.Presenter)

function Dialogue.init(_api: any) end

return Dialogue
