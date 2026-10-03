local MarkerTranslator = {}

-- Keep marker-to-event translation in one place so marker enums can be added later.
function MarkerTranslator.ToEventName(markerName: string): string
	return markerName
end

return MarkerTranslator
