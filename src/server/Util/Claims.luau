-- First-come claims for handshakes, where two sides that can't talk first still need exactly one of them to win.
-- Internal only, not part of the public API (Core only exposes API/v1/Modules).
--
-- Two shapes:
--   Claims.newPair<K>()      a lock on two keys at once, the same from either side (e.g. a friend request in flight)
--   Claims.newSingle<K, H>() one key owned by one holder, with a lookup of who holds it (e.g. who called out a target)
--
-- Each system made by a constructor is its own store, so different kinds of handshake never block each other.
--
-- Claiming never yields, which is what makes it decide who got there first: the check and the set happen with no other
-- thread in between. Whatever the holder does next can yield (a mod hook, a function call on the other side), which is
-- why a claim is held across it and released after. When a claim fails, looking up the current one right after is
-- safe for the same reason: neither step yields.
--
-- A claim is its own identity. Whoever made it can tell it apart from a newer claim on the same key or pair, so
-- releasing a stale claim (the key was opened and claimed again meanwhile) does nothing.

local Claims = {}

export type Claim = {}

export type PairClaims<K> = {
	-- The new claim on the pair, or nil if the pair is already claimed. With a timeout (seconds) the claim ends on its own
	-- after that long, a backstop for a holder that never gets to release (a request that hangs)
	claim: (a: K, b: K, timeout: number?) -> Claim?,
	-- Opens the pair if it is still held by this claim. True if it was released
	release: (a: K, b: K, claim: Claim) -> boolean,
	-- The claim currently on the pair, if any
	get: (a: K, b: K) -> Claim?,
	isClaimed: (a: K, b: K) -> boolean,
	-- Opens every pair the key is part of, e.g. when a character is gone and can't finish what it started
	releaseAll: (key: K) -> (),
}

export type SingleClaims<K, H> = {
	-- The new claim on the key for this holder, or nil if anyone (this holder included) already holds it. With a
	-- timeout (seconds) the claim ends on its own after that long; without one it lasts until released
	claim: (key: K, holder: H, timeout: number?) -> Claim?,
	-- Opens the key if it is still held by this claim. True if it was released
	release: (key: K, claim: Claim) -> boolean,
	-- Who holds the key right now, if anyone
	getHolder: (key: K) -> H?,
	-- The claim currently on the key, if any
	get: (key: K) -> Claim?,
	isClaimed: (key: K) -> boolean,
	-- Opens the key whoever holds it, e.g. when the claimed thing is gone
	clear: (key: K) -> (),
	-- Opens every key this holder holds, e.g. when the holder is gone
	releaseHolder: (holder: H) -> (),
}

function Claims.newPair<K>(): PairClaims<K>
	local claims: { [K]: { [K]: Claim } } = {}

	local function set(from: K, to: K, claim: Claim?)
		local partners = claims[from]
		if not partners then
			if not claim then
				return
			end
			partners = {}
			claims[from] = partners
		end

		partners[to] = claim
		if next(partners) == nil then
			claims[from] = nil
		end
	end

	local function get(a: K, b: K): Claim?
		local partners = claims[a]
		return if partners then partners[b] else nil
	end

	local function release(a: K, b: K, held: Claim): boolean
		if get(a, b) ~= held then
			return false
		end

		set(a, b, nil)
		set(b, a, nil)
		return true
	end

	local function claim(a: K, b: K, timeout: number?): Claim?
		if get(a, b) then
			return nil
		end

		local newClaim: Claim = {}
		set(a, b, newClaim)
		set(b, a, newClaim)

		if timeout then
			-- Released through the claim, so a pair that was opened and claimed again meanwhile is left alone
			task.delay(timeout, release, a, b, newClaim)
		end
		return newClaim
	end

	local function isClaimed(a: K, b: K): boolean
		return get(a, b) ~= nil
	end

	local function releaseAll(key: K)
		local partners = claims[key]
		if not partners then
			return
		end

		for partner in partners do
			set(partner, key, nil)
		end
		claims[key] = nil
	end

	return {
		claim = claim,
		release = release,
		get = get,
		isClaimed = isClaimed,
		releaseAll = releaseAll,
	}
end

function Claims.newSingle<K, H>(): SingleClaims<K, H>
	type Entry = {
		Claim: Claim,
		Holder: H,
		ExpiresAt: number?,
	}

	local entries: { [K]: Entry } = {}
	-- The reverse of entries, so a holder that leaves can open its keys without a search
	local heldBy: { [H]: { [K]: true } } = {}

	-- The one place both indexes change, so they never disagree
	local function remove(key: K)
		local entry = entries[key]
		if not entry then
			return
		end

		entries[key] = nil
		local keys = heldBy[entry.Holder]
		if keys then
			keys[key] = nil
			if next(keys) == nil then
				heldBy[entry.Holder] = nil
			end
		end
	end

	-- The entry on the key if it hasn't lapsed. The timer in claim does the real cleanup; this covers the moment between
	-- the claim's end and the timer firing, so a lookup is exact to the time given
	local function live(key: K): Entry?
		local entry = entries[key]
		if entry and entry.ExpiresAt and os.clock() >= entry.ExpiresAt then
			remove(key)
			return nil
		end
		return entry
	end

	local function release(key: K, held: Claim): boolean
		local entry = live(key)
		if not entry or entry.Claim ~= held then
			return false
		end

		remove(key)
		return true
	end

	local function claim(key: K, holder: H, timeout: number?): Claim?
		if live(key) then
			return nil
		end

		local newClaim: Claim = {}
		entries[key] = {
			Claim = newClaim,
			Holder = holder,
			ExpiresAt = if timeout then os.clock() + timeout else nil,
		}

		local keys = heldBy[holder]
		if not keys then
			keys = {}
			heldBy[holder] = keys
		end
		keys[key] = true

		if timeout then
			-- Checked against the claim itself, so a key that was opened and claimed again meanwhile is left alone
			task.delay(timeout, function()
				local entry = entries[key]
				if entry and entry.Claim == newClaim then
					remove(key)
				end
			end)
		end
		return newClaim
	end

	local function getHolder(key: K): H?
		local entry = live(key)
		return if entry then entry.Holder else nil
	end

	local function get(key: K): Claim?
		local entry = live(key)
		return if entry then entry.Claim else nil
	end

	local function isClaimed(key: K): boolean
		return live(key) ~= nil
	end

	local function releaseHolder(holder: H)
		local keys = heldBy[holder]
		if not keys then
			return
		end

		for key in keys do
			entries[key] = nil
		end
		heldBy[holder] = nil
	end

	return {
		claim = claim,
		release = release,
		getHolder = getHolder,
		get = get,
		isClaimed = isClaimed,
		clear = remove,
		releaseHolder = releaseHolder,
	}
end

return Claims
