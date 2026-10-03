local TypeModuleResponse = {}

export type ModuleResponse = {
	Success: boolean,
	PassResponse: boolean,
	StatusCode: number?,
	Message: string?,
	Data: any?,
}

return TypeModuleResponse
