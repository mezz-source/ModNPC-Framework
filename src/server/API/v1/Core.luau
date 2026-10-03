local API = require(script.Parent.API)
local Core = {}

local Modules = script.Parent.Modules

function Core.init()
	print("V1 Core initialized")
	local modules = {}
	for _, module: ModuleScript in ipairs(Modules:GetChildren()) do
		local moduleName = module.Name
		local moduleTable = require(module)
		local success, err = pcall(function()
			moduleTable.init(API)
		end)

		if not success then
			warn("Failed to initialize module:", moduleName, err)
		end

		modules[moduleName] = moduleTable
	end

	API.init(modules)
end

return Core
