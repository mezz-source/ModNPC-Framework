local TypeVFX = {}

-- Where a particle lives. A part is used as it is, and a model resolves to its part (a character's root part, a weapon's
-- part), so the particle follows it. A Vector3 or CFrame is a fixed spot in the world, the CFrame also aiming the emitter.
export type ParticleLocation = BasePart | Model | Vector3 | CFrame

-- A particle is a plain table of closures rather than a metatable class: the API hands it back through a
-- BindableFunction, which copies tables and strips metatables. Methods are still called with a colon, and every copy
-- drives the same particle. Once the particle is destroyed every method is a no-op.
-- It starts disabled with nothing emitted, and stays until Destroy, its part going or the character that made it going.
export type Particle = {
	Name: string,
	-- Emits that many particles at once; the effect's EmitCount when left out
	Emit: (self: Particle, count: number?) -> (),
	-- Emits continuously at the template's Rate until Disable
	Enable: (self: Particle) -> (),
	-- Stops emitting; particles already out live out their lifetime
	Disable: (self: Particle) -> (),
	IsEnabled: (self: Particle) -> boolean,
	IsDestroyed: (self: Particle) -> boolean,
	-- Removes the emitter at once, along with any particles still out
	Destroy: (self: Particle) -> (),
}

return TypeVFX
