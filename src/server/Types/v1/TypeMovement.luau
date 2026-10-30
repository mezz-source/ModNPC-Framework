local TypeMovement = {}

export type MovementDirection = "Left" | "Right" | "Forward" | "Backward"
-- One direction, or several walked at once (Forward + Left is a diagonal, opposites cancel out)
export type MovementDirections = MovementDirection | { MovementDirection }

TypeMovement.MovementEnum = table.freeze({
	Left = "Left",
	Right = "Right",
	Forward = "Forward",
	Backward = "Backward",
})

return TypeMovement
