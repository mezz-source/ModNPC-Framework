local TypeRequest = {}

export type APIRequest = {
	ModuleName: string,
	Function: string,
	Arguments: any,
}

export type APIResponse = {
	Success: boolean,
	StatusCode: number,
	Message: string?,
	Data: any?,
}

export type CharacterResponse = {
	Success: boolean,
	Message: string?,
	Data: any?,
}

TypeRequest.Enums = table.freeze({
	StatusCode = {
		Success = 200,
		BadRequest = 400,
		MalformedRequest = 422,
		NotFound = 404,
		Conflict = 409,
		Gone = 410,
		InternalServerError = 500,
	},
})

return TypeRequest
