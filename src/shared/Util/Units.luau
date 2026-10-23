--[[
	Unit conversion. Roblox convention: 1 stud = 0.28 metres.
]]

local METERS_PER_STUD = 0.28

local Units = {}

function Units.StudsPerSecondToKmh(studsPerSecond: number): number
	return studsPerSecond * METERS_PER_STUD * 3.6
end

return Units
