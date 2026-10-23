--[[
	Create(className, properties, children?) -> Instance
	Parent is assigned last so the instance is fully configured before it replicates or renders.
]]

return function(className: string, properties: { [string]: any }?, children: { Instance }?): any
	local instance = Instance.new(className)
	local parent = nil

	for key, value in properties or {} do
		if key == "Parent" then
			parent = value
		else
			(instance :: any)[key] = value
		end
	end

	for _, child in children or {} do
		child.Parent = instance
	end

	if parent then
		instance.Parent = parent
	end

	return instance
end
