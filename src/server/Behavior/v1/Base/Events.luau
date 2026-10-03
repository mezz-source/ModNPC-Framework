local Events = {}
Events.__index = Events

Events.SubscribeEnum = table.freeze({
	First = "First",
	Last = "Last",
})

function Events.new(Base: {})
	local self = setmetatable({}, Events)
	self.Base = Base
	self.Subscriptions = {}
	return self
end

function Events:Subscribe(eventName: string, callback: (any?) -> (), once: boolean?, position: string?)
	local subscriptions = self.Subscriptions[eventName]
	if not subscriptions then
		subscriptions = {}
		self.Subscriptions[eventName] = subscriptions
	end

	local subscription = {
		Callback = callback,
		Once = once == true,
		Active = true,
	}

	if position == Events.SubscribeEnum.First then
		table.insert(subscriptions, 1, subscription)
	else
		table.insert(subscriptions, subscription)
	end

	subscription.Unsubscribe = function()
		return self:Unsubscribe(eventName, subscription)
	end

	return subscription
end

function Events:Unsubscribe(eventName: string, subscriptionOrCallback): boolean
	local subscriptions = self.Subscriptions[eventName]
	if not subscriptions then
		return false
	end

	for index, current in ipairs(subscriptions) do
		if current == subscriptionOrCallback or current.Callback == subscriptionOrCallback then
			if not current.Active then
				return false
			end

			current.Active = false
			table.remove(subscriptions, index)
			if #subscriptions == 0 then
				self.Subscriptions[eventName] = nil
			end

			return true
		end
	end

	return false
end

function Events:Dispatch(eventName: string, arguments: any?)
	local subscriptions = self.Subscriptions[eventName]
	if not subscriptions then
		return false
	end

	local dispatched = false
	local snapshot = table.clone(subscriptions)
	for _, subscription in ipairs(snapshot) do
		if subscription.Active then
			dispatched = true
			if subscription.Once then
				self:Unsubscribe(eventName, subscription)
			end

			local success, errorMessage = pcall(subscription.Callback, arguments)
			if not success then
				warn("Character event failed:", eventName, errorMessage)
			end
		end
	end

	return dispatched
end

function Events:Destroy()
	self.Subscriptions = {}
	self.Base = nil
end

return Events
