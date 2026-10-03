local TypeMovement = {}

export type MovementDirection = "Left" | "Right" | "Forward" | "Backward"

TypeMovement.MovementEnum = table.freeze({
	Left = "Left",
	Right = "Right",
	Forward = "Forward",
	Backward = "Backward",
})

return TypeMovement
