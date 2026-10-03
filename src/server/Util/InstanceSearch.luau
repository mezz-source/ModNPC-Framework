local InstanceSearch = {}

local function hasClass(instance: Instance, className: string?): boolean
	return className == nil or instance:IsA(className)
end

local function findChildPath(root: Instance, path: { string }, className: string?): Instance?
	local current: Instance? = root

	for _, name in ipairs(path) do
		if not current then
			return nil
		end

		current = current:FindFirstChild(name)
	end

	if not current or not hasClass(current, className) then
		return nil
	end

	return current
end

local function findDescendantsByName(root: Instance, name: string, className: string?): { Instance }
	local matches = {}

	for _, descendant in ipairs(root:GetDescendants()) do
		if descendant.Name == name and hasClass(descendant, className) then
			table.insert(matches, descendant)
		end
	end

	table.sort(matches, function(left, right)
		return left:GetFullName() < right:GetFullName()
	end)

	return matches
end

local function findNamedDescendants(root: Instance, name: string): { Instance }
	local matches = {}

	for _, descendant in ipairs(root:GetDescendants()) do
		if descendant.Name == name then
			table.insert(matches, descendant)
		end
	end

	return matches
end

function InstanceSearch.findPath(root: Instance, path: { string }, className: string?): Instance?
	return findChildPath(root, path, className)
end

function InstanceSearch.findUnique(root: Instance, name: string, className: string?): (Instance?, string?)
	local matches = findDescendantsByName(root, name, className)

	if #matches == 0 then
		return nil, "NotFound"
	end

	if #matches > 1 then
		return nil, "Ambiguous"
	end

	return matches[1], nil
end

function InstanceSearch.findAll(root: Instance, name: string, className: string?): { Instance }
	return findDescendantsByName(root, name, className)
end

function InstanceSearch.find(
	root: Instance,
	name: string,
	className: string?
): {
	Status: string,
	Instance: Instance?,
	Matches: { Instance }?,
	Message: string?,
}
	local namedMatches = findNamedDescendants(root, name)
	local matches = findDescendantsByName(root, name, className)

	if #namedMatches == 0 then
		return { Status = "NotFound", Message = "No matching descendant found" }
	end

	if #matches == 0 then
		return {
			Status = "InvalidClass",
			Matches = namedMatches,
			Message = "Matching descendants have an invalid class",
		}
	end

	if #matches > 1 then
		return { Status = "Ambiguous", Matches = matches, Message = "Multiple matching descendants found" }
	end

	return { Status = "Found", Instance = matches[1], Matches = matches }
end

function InstanceSearch.getPrimitiveValue(instance: Instance): (boolean, any, string?)
	if not instance:IsA("ValueBase") then
		return false, nil, "Instance is not a ValueBase"
	end

	local value = (instance :: any).Value
	local valueType = typeof(value)
	if valueType ~= "boolean" and valueType ~= "number" and valueType ~= "string" then
		return false, nil, "ValueBase does not contain a supported primitive"
	end

	return true, value, nil
end

return InstanceSearch
