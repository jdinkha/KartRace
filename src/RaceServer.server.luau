--[[
	RaceServer  —  a normal Script that goes in ServerScriptService

	Kart racing MVP, server side. This script:
	  • builds the lobby and one linear race track out of parts when the game starts
	  • runs the game loop: lobby -> intermission -> race -> back to lobby -> repeat
	  • tracks checkpoints, live race positions, finish times and respawns
	  • keeps a global "most 1st places" leaderboard saved with DataStores

	It pairs with the RaceClient LocalScript (StarterPlayer > StarterPlayerScripts),
	which handles driving, the camera and the on-screen UI.

	Want to decorate the map by hand? Press Play, copy Workspace.RaceTrack (and/or
	Workspace.RaceLobby), press Stop, and paste it into Workspace. When those folders
	already exist, this script uses them instead of generating new ones.
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local PhysicsService = game:GetService("PhysicsService")
local DataStoreService = game:GetService("DataStoreService")

------------------------------------------------------------------------
-- SETTINGS  (safe to tweak)
------------------------------------------------------------------------
local SETTINGS = {
	INTERMISSION_TIME = 1, -- seconds in the lobby before each race (currently 1 to quickly test the track)
	COUNTDOWN_TIME = 3, -- 3, 2, 1, GO!
	RACE_TIME_LIMIT = 120, -- hard limit on race length, in seconds
	TIME_AFTER_FIRST_FINISH = 30, -- once 1st place finishes, everyone else gets this long
	RETURN_DELAY = 4, -- seconds a finisher stays on the track before going back to the lobby
	MIN_PLAYERS_TO_START = 1, -- 1 lets you race alone (handy for testing)
	MIN_RACERS_FOR_WIN = 2, -- a 1st place only counts on the leaderboard with at least this many racers
	MAX_RACERS = 12, -- size of the starting grid; extra players wait for the next race
	RESPAWN_COOLDOWN = 1.5, -- seconds between manual respawns
	LEADERBOARD_SIZE = 10,
	LEADERBOARD_REFRESH = 60, -- seconds between leaderboard refreshes
	DATASTORE_NAME = "GlobalWins_v1", -- rename to start a fresh leaderboard
}

------------------------------------------------------------------------
-- TRACK  —  the road is a smooth curve through POINTS, in order.
-- X/Z move it around the map, Y makes hills. Edit, press Play, and the
-- track rebuilds itself. Keep neighbouring points roughly 100-150 apart.
------------------------------------------------------------------------
local TRACK = {
	ORIGIN = Vector3.new(-800, 120, 0), -- where point (0, 0, 0) sits in the world
	ROAD_WIDTH = 36,
	WALL_HEIGHT = 4,
	STEP = 10, -- length of each road piece (smaller = smoother but more parts)
	PRE_START = 80, -- road behind the start line (room for the starting grid)
	RUN_OFF = 70, -- road after the finish line
	CHECKPOINT_SPACING = 100,

	POINTS = {
		Vector3.new(0, 0, -80), --  1 back of the starting grid
		Vector3.new(0, 0, 60), --  2 start straight
		Vector3.new(0, 0, 200), --  3
		Vector3.new(30, 0, 320), --  4 long sweeper
		Vector3.new(120, 0, 420), --  5
		Vector3.new(250, 0, 450), --  6
		Vector3.new(370, 0, 400), --  7
		Vector3.new(430, 0, 290), --  8 turning back
		Vector3.new(420, 8, 170), --  9 climb
		Vector3.new(360, 20, 70), -- 10
		Vector3.new(380, 28, -50), -- 11 crest
		Vector3.new(480, 20, -120), -- 12 downhill
		Vector3.new(600, 6, -110), -- 13
		Vector3.new(700, 0, -40), -- 14 S-bends
		Vector3.new(745, 0, 80), -- 15
		Vector3.new(715, 0, 190), -- 16
		Vector3.new(765, 0, 285), -- 17
		Vector3.new(870, 0, 320), -- 18 long straight
		Vector3.new(1000, 0, 320), -- 19
		Vector3.new(1150, 0, 320), -- 20 jump ramp
		Vector3.new(1300, 0, 320), -- 21
		Vector3.new(1420, 0, 280), -- 22 big sweeping turn
		Vector3.new(1480, 0, 170), -- 23
		Vector3.new(1450, 0, 50), -- 24
		Vector3.new(1360, -6, -40), -- 25 dip
		Vector3.new(1260, -10, -140), -- 26
		Vector3.new(1260, -10, -270), -- 27
		Vector3.new(1340, -6, -370), -- 28
		Vector3.new(1460, 0, -400), -- 29 finish straight
		Vector3.new(1600, 0, -400), -- 30
		Vector3.new(1720, 0, -400), -- 31 end of the run-off
	},

	-- Things placed on the road. `point` = which POINT it sits at,
	-- `lane` = sideways offset from the centre line (negative = left).
	FEATURES = {
		{ kind = "Boost", point = 3, lane = 0 },
		{ kind = "Boost", point = 13, lane = -8 },
		{ kind = "Boost", point = 19, lane = -9 },
		{ kind = "Boost", point = 19, lane = 9 },
		{ kind = "Ramp", point = 20, lane = 0 },
		{ kind = "Boost", point = 27, lane = 8 },
		{ kind = "Boost", point = 30, lane = 0 },
	},
}

local COLORS = {
	Road = Color3.fromRGB(58, 58, 66),
	CurbA = Color3.fromRGB(225, 45, 45),
	CurbB = Color3.fromRGB(245, 245, 245),
	Wall = Color3.fromRGB(60, 140, 255),
	Pillar = Color3.fromRGB(150, 150, 160),
	Boost = Color3.fromRGB(255, 150, 20),
	Ramp = Color3.fromRGB(255, 210, 40),
	LobbyFloor = Color3.fromRGB(110, 200, 120),
	Board = Color3.fromRGB(25, 25, 40),
	Gold = Color3.fromRGB(255, 215, 70),
	White = Color3.fromRGB(245, 245, 245),
	Black = Color3.fromRGB(25, 25, 25),
	Dark = Color3.fromRGB(35, 35, 40),
}

local KART_COLORS = {
	Color3.fromRGB(230, 60, 60),
	Color3.fromRGB(60, 130, 240),
	Color3.fromRGB(70, 200, 90),
	Color3.fromRGB(250, 200, 40),
	Color3.fromRGB(170, 80, 230),
	Color3.fromRGB(250, 130, 30),
	Color3.fromRGB(40, 210, 210),
	Color3.fromRGB(240, 100, 180),
	Color3.fromRGB(240, 240, 240),
	Color3.fromRGB(60, 60, 70),
	Color3.fromRGB(140, 230, 60),
	Color3.fromRGB(150, 100, 60),
}

------------------------------------------------------------------------
-- Shared objects the client script listens to
------------------------------------------------------------------------
local raceState = Instance.new("Folder")
raceState.Name = "RaceState"
raceState:SetAttribute("Phase", "Waiting") -- Waiting / Intermission / Countdown / Racing / Results
raceState:SetAttribute("Countdown", 0)
raceState:SetAttribute("RaceStart", 0)
raceState:SetAttribute("RaceEnd", 0)
raceState:SetAttribute("RacerCount", 0)
raceState.Parent = ReplicatedStorage

local raceEvent = Instance.new("RemoteEvent")
raceEvent.Name = "RaceEvent"
raceEvent.Parent = ReplicatedStorage

------------------------------------------------------------------------
-- Small helpers
------------------------------------------------------------------------
local function newPart(className: string, props: { [string]: any }, parent: Instance): BasePart
	local part = (Instance.new(className) :: any) :: BasePart
	part.Anchored = true
	part.TopSurface = Enum.SurfaceType.Smooth
	part.BottomSurface = Enum.SurfaceType.Smooth
	part.Material = Enum.Material.SmoothPlastic
	for key, value in props do
		(part :: any)[key] = value
	end
	part.Parent = parent
	return part
end

-- A part you can't bump into, stand on, or hit with raycasts (pure decoration/markers)
local function ghost(props: { [string]: any }): { [string]: any }
	props.CanCollide = false
	props.CanQuery = false
	props.CanTouch = false
	return props
end

local function newLabel(props: { [string]: any }, parent: Instance): TextLabel
	local label = Instance.new("TextLabel")
	label.BackgroundTransparency = 1
	label.TextColor3 = COLORS.White
	label.Font = Enum.Font.FredokaOne
	label.TextScaled = true
	label.TextWrapped = true
	for key, value in props do
		(label :: any)[key] = value
	end
	label.Parent = parent
	return label
end

local function newSurfaceGui(part: BasePart, face: Enum.NormalId, name: string?): SurfaceGui
	local gui = Instance.new("SurfaceGui")
	gui.Name = name or "SurfaceGui"
	gui.Face = face
	gui.SizingMode = Enum.SurfaceGuiSizingMode.PixelsPerStud
	gui.PixelsPerStud = 40
	gui.LightInfluence = 0
	gui.Parent = part
	return gui
end

local function newFolder(name: string, parent: Instance): Folder
	local folder = Instance.new("Folder")
	folder.Name = name
	folder.Parent = parent
	return folder
end

-- CFrame at `pos` facing along `dir`, kept level (no tilt)
local function flatCFrame(pos: Vector3, dir: Vector3): CFrame
	local flat = Vector3.new(dir.X, 0, dir.Z)
	if flat.Magnitude < 1e-3 then
		flat = Vector3.zAxis
	end
	return CFrame.lookAt(pos, pos + flat.Unit)
end

------------------------------------------------------------------------
-- TRACK BUILDER
------------------------------------------------------------------------
local function catmullRom(p0: Vector3, p1: Vector3, p2: Vector3, p3: Vector3, t: number): Vector3
	local t2 = t * t
	local t3 = t2 * t
	return (
		(p1 * 2)
		+ (p2 - p0) * t
		+ (p0 * 2 - p1 * 5 + p2 * 4 - p3) * t2
		+ (p1 * 3 - p0 - p2 * 3 + p3) * t3
	) * 0.5
end

-- Turns the control points into evenly spaced points along a smooth curve.
local function sampleTrack(): ({ Vector3 }, { number })
	local pts = {}
	for i, p in TRACK.POINTS do
		pts[i] = TRACK.ORIGIN + p
	end

	local samples: { Vector3 } = {}
	local pointToSample: { number } = {}
	for i = 1, #pts - 1 do
		local p1, p2 = pts[i], pts[i + 1]
		local p0 = pts[i - 1] or (p1 * 2 - p2)
		local p3 = pts[i + 2] or (p2 * 2 - p1)
		pointToSample[i] = #samples + 1
		local steps = math.max(1, math.ceil((p2 - p1).Magnitude / TRACK.STEP))
		for s = 0, steps - 1 do
			table.insert(samples, catmullRom(p0, p1, p2, p3, s / steps))
		end
	end
	table.insert(samples, pts[#pts])
	pointToSample[#pts] = #samples
	return samples, pointToSample
end

local function buildArch(cf: CFrame, text: string, parent: Instance)
	local width = TRACK.ROAD_WIDTH
	for _, side in { -1, 1 } do
		newPart("Part", {
			Name = "ArchPost",
			Size = Vector3.new(2, 18, 2),
			CFrame = cf * CFrame.new(side * (width / 2 + 2.5), 9, 0),
			Color = COLORS.White,
		}, parent)
	end
	local banner = newPart("Part", {
		Name = "ArchBanner",
		Size = Vector3.new(width + 7, 4, 1.5),
		CFrame = cf * CFrame.new(0, 17, 0),
		Color = COLORS.Board,
	}, parent)
	for _, face in { Enum.NormalId.Front, Enum.NormalId.Back } do
		local gui = newSurfaceGui(banner, face)
		newLabel({ Size = UDim2.fromScale(1, 1), Text = text, TextColor3 = COLORS.Gold }, gui)
	end
end

local function buildTrack(): Folder
	local track = Instance.new("Folder")
	track.Name = "RaceTrack"
	local road = newFolder("Road", track) -- solid stuff karts drive on / bump into
	local decor = newFolder("Decor", track) -- visuals only
	local checkpointFolder = newFolder("Checkpoints", track)
	local slotFolder = newFolder("StartSlots", track)

	local samples, pointToSample = sampleTrack()
	local dist = { 0 }
	for i = 2, #samples do
		dist[i] = dist[i - 1] + (samples[i] - samples[i - 1]).Magnitude
	end
	local total = dist[#dist]

	-- Position + direction at a given distance along the road
	local function pointAt(d: number): (Vector3, Vector3)
		d = math.clamp(d, 0, total)
		for i = 1, #samples - 1 do
			if dist[i + 1] >= d then
				local segLen = dist[i + 1] - dist[i]
				local alpha = if segLen > 0 then (d - dist[i]) / segLen else 0
				return samples[i]:Lerp(samples[i + 1], alpha), (samples[i + 1] - samples[i]).Unit
			end
		end
		local n = #samples
		return samples[n], (samples[n] - samples[n - 1]).Unit
	end

	local width = TRACK.ROAD_WIDTH
	local minY = math.huge

	-- Road, curbs, walls and support pillars, one short piece at a time.
	-- Pieces overlap a little so curves don't leave gaps.
	for i = 1, #samples - 1 do
		local a, b = samples[i], samples[i + 1]
		local len = (b - a).Magnitude
		minY = math.min(minY, a.Y, b.Y)
		if len < 0.01 then
			continue
		end
		local cf = CFrame.lookAt((a + b) / 2, b) -- centre of the road surface

		newPart("Part", {
			Name = "Road",
			Size = Vector3.new(width, 1, len + 5),
			CFrame = cf * CFrame.new(0, -0.5, 0),
			Color = COLORS.Road,
			Material = Enum.Material.Asphalt,
		}, road)

		local curbColor = if i % 2 == 0 then COLORS.CurbA else COLORS.CurbB
		for _, side in { -1, 1 } do
			newPart("Part", ghost({
				Name = "Curb",
				Size = Vector3.new(2.5, 0.1, len + 0.6),
				CFrame = cf * CFrame.new(side * (width / 2 - 1.25), 0.03 + (i % 2) * 0.01, 0),
				Color = curbColor,
			}), decor)
			newPart("Part", {
				Name = "Wall",
				Size = Vector3.new(1.5, TRACK.WALL_HEIGHT + 1, len + 5),
				CFrame = cf * CFrame.new(side * (width / 2 + 0.75), (TRACK.WALL_HEIGHT - 1) / 2, 0),
				Color = COLORS.Wall,
			}, road)
		end

		if i % 20 == 0 and a.Y > 6 then
			local height = a.Y - 1
			newPart("Part", ghost({
				Name = "Pillar",
				Size = Vector3.new(6, height, 6),
				CFrame = CFrame.new(a.X, height / 2, a.Z),
				Color = COLORS.Pillar,
				Material = Enum.Material.Concrete,
			}), decor)
		end
	end

	-- Boost pads and ramps
	for _, feature in TRACK.FEATURES do
		local index = pointToSample[feature.point]
		if not index then
			continue
		end
		local pos, dir = pointAt(dist[index])
		local flat = flatCFrame(pos, dir)
		local center = pos + flat.RightVector * (feature.lane or 0)

		if feature.kind == "Boost" then
			local pad = newPart("Part", {
				Name = "BoostPad",
				Size = Vector3.new(10, 0.2, 16),
				CFrame = CFrame.lookAt(center, center + dir) * CFrame.new(0, -0.04, 0),
				Color = COLORS.Boost,
				Material = Enum.Material.Neon,
				CanCollide = false, -- karts drive over it; the client detects it with a raycast
			}, road)
			pad:SetAttribute("BoostPad", true)
		elseif feature.kind == "Ramp" then
			local length, angle = 18, math.rad(14)
			local endPoint = center + flat.LookVector * (length * math.cos(angle)) + Vector3.yAxis * (length * math.sin(angle))
			local slope = CFrame.lookAt((center + endPoint) / 2, endPoint)
			newPart("Part", {
				Name = "Ramp",
				Size = Vector3.new(width - 2, 1, length),
				CFrame = slope * CFrame.new(0, -0.5, 0),
				Color = COLORS.Ramp,
			}, road)
			local supportHeight = endPoint.Y - 1.1 - center.Y
			local supportPos = Vector3.new(endPoint.X, center.Y + supportHeight / 2, endPoint.Z) - flat.LookVector * 1.2
			newPart("Part", {
				Name = "RampSupport",
				Size = Vector3.new(width - 2, supportHeight, 1),
				CFrame = flatCFrame(supportPos, dir),
				Color = COLORS.Dark,
			}, road)
		end
	end

	-- Start line, finish line, arches and end walls
	local startDist = TRACK.PRE_START
	local finishDist = total - TRACK.RUN_OFF
	local startPos, startDir = pointAt(startDist)
	local startCF = flatCFrame(startPos, startDir)
	newPart("Part", ghost({
		Name = "StartLine",
		Size = Vector3.new(width, 0.1, 2),
		CFrame = startCF * CFrame.new(0, 0.05, 0),
		Color = COLORS.White,
	}), track)
	buildArch(startCF, "START", decor)

	local finishPos, finishDir = pointAt(finishDist)
	local finishCF = CFrame.lookAt(finishPos, finishPos + finishDir)
	local tiles = 12
	local tileWidth = width / tiles
	for row = 0, 1 do
		for col = 0, tiles - 1 do
			newPart("Part", ghost({
				Name = "FinishTile",
				Size = Vector3.new(tileWidth, 0.1, 2),
				CFrame = finishCF * CFrame.new(-width / 2 + tileWidth * (col + 0.5), 0.05, (row - 0.5) * 2),
				Color = if (row + col) % 2 == 0 then COLORS.Black else COLORS.White,
			}), decor)
		end
	end
	buildArch(flatCFrame(finishPos, finishDir), "FINISH", decor)

	local n = #samples
	local wallHeight = TRACK.WALL_HEIGHT + 4
	newPart("Part", {
		Name = "EndWall",
		Size = Vector3.new(width + 3, wallHeight, 2),
		CFrame = flatCFrame(samples[n], samples[n] - samples[n - 1]) * CFrame.new(0, wallHeight / 2 - 1, 1),
		Color = COLORS.Wall,
	}, road)
	newPart("Part", {
		Name = "BackWall",
		Size = Vector3.new(width + 3, wallHeight, 2),
		CFrame = flatCFrame(samples[1], samples[2] - samples[1]) * CFrame.new(0, wallHeight / 2 - 1, 1),
		Color = COLORS.Wall,
	}, road)

	-- Invisible checkpoint "gates". Racers must pass them in order; the last one is the finish.
	local raceLength = finishDist - startDist
	local count = math.max(1, math.floor(raceLength / TRACK.CHECKPOINT_SPACING))
	for k = 1, count do
		local pos, dir = pointAt(startDist + raceLength * (k / count))
		newPart("Part", ghost({
			Name = tostring(k),
			Size = Vector3.new(width + 24, 40, 2),
			CFrame = CFrame.lookAt(pos, pos + dir),
			Transparency = 1,
		}), checkpointFolder)
	end

	-- Starting grid: rows of three behind the start line
	for k = 1, SETTINGS.MAX_RACERS do
		local row = math.floor((k - 1) / 3)
		local col = (k - 1) % 3
		local back = 12 + row * 12 + (if col == 1 then 5 else 0)
		local pos, dir = pointAt(startDist - back)
		local base = flatCFrame(pos, dir)
		local slotCF = base * CFrame.new((col - 1) * 10, 0, 0)
		newPart("Part", ghost({
			Name = tostring(k),
			Size = Vector3.new(6, 0.1, 8),
			CFrame = slotCF,
			Transparency = 1,
		}), slotFolder)
		newPart("Part", ghost({
			Name = "GridMark",
			Size = Vector3.new(6, 0.1, 0.6),
			CFrame = slotCF * CFrame.new(0, 0.05, -4.5),
			Color = COLORS.White,
		}), decor)
	end

	track:SetAttribute("KillY", minY - 40) -- fall below this = respawn at last checkpoint
	track.Parent = workspace
	return track
end

------------------------------------------------------------------------
-- LOBBY BUILDER
------------------------------------------------------------------------
local function buildLobby(): Folder
	local lobby = Instance.new("Folder")
	lobby.Name = "RaceLobby"
	local center = TRACK.ORIGIN + Vector3.new(-110, 0, 0)
	local size = 80

	newPart("Part", {
		Name = "Floor",
		Size = Vector3.new(size, 2, size),
		CFrame = CFrame.new(center - Vector3.new(0, 1, 0)),
		Color = COLORS.LobbyFloor,
		Material = Enum.Material.Grass,
	}, lobby)

	-- See-through railings so nobody falls off
	for _, offset in { Vector3.new(size / 2, 0, 0), Vector3.new(-size / 2, 0, 0), Vector3.new(0, 0, size / 2), Vector3.new(0, 0, -size / 2) } do
		newPart("Part", {
			Name = "Railing",
			Size = if offset.X == 0 then Vector3.new(size, 6, 1) else Vector3.new(1, 6, size),
			CFrame = CFrame.new(center + offset + Vector3.new(0, 3, 0)),
			Color = Color3.fromRGB(200, 230, 255),
			Material = Enum.Material.Glass,
			Transparency = 0.7,
		}, lobby)
	end

	local spawn = newPart("SpawnLocation", {
		Name = "LobbySpawn",
		Size = Vector3.new(12, 1, 12),
		CFrame = CFrame.new(center + Vector3.new(0, 0.5, 0)),
		Color = COLORS.White,
	}, lobby) :: SpawnLocation
	spawn.Neutral = true
	spawn.Duration = 0 -- no spawn force field

	-- Global leaderboard board
	local boardPos = center + Vector3.new(-size / 2 + 4, 10, 0)
	local board = newPart("Part", {
		Name = "LeaderboardBoard",
		Size = Vector3.new(28, 18, 1),
		CFrame = CFrame.lookAt(boardPos, Vector3.new(center.X, boardPos.Y, center.Z)),
		Color = COLORS.Board,
	}, lobby)
	local gui = newSurfaceGui(board, Enum.NormalId.Front, "Leaderboard")
	newLabel({ Name = "Title", Size = UDim2.fromScale(1, 0.14), Text = "🏆 MOST 1ST PLACES — ALL TIME", TextColor3 = COLORS.Gold }, gui)
	local list = Instance.new("Frame")
	list.Name = "List"
	list.BackgroundTransparency = 1
	list.Position = UDim2.fromScale(0.04, 0.16)
	list.Size = UDim2.fromScale(0.92, 0.76)
	list.Parent = gui
	local layout = Instance.new("UIListLayout")
	layout.SortOrder = Enum.SortOrder.LayoutOrder
	layout.Parent = list
	for rank = 1, SETTINGS.LEADERBOARD_SIZE do
		local row = Instance.new("Frame")
		row.Name = "Row" .. rank
		row.LayoutOrder = rank
		row.Size = UDim2.fromScale(1, 1 / SETTINGS.LEADERBOARD_SIZE)
		row.BackgroundColor3 = COLORS.White
		row.BackgroundTransparency = if rank % 2 == 1 then 0.9 else 1
		row.BorderSizePixel = 0
		row.Parent = list
		newLabel({ Name = "Rank", Size = UDim2.fromScale(0.12, 0.8), Position = UDim2.fromScale(0.01, 0.1), Text = "#" .. rank, TextXAlignment = Enum.TextXAlignment.Left }, row)
		newLabel({ Name = "PlayerName", Size = UDim2.fromScale(0.6, 0.8), Position = UDim2.fromScale(0.14, 0.1), Text = "—", TextXAlignment = Enum.TextXAlignment.Left }, row)
		newLabel({ Name = "Wins", Size = UDim2.fromScale(0.24, 0.8), Position = UDim2.fromScale(0.75, 0.1), Text = "", TextXAlignment = Enum.TextXAlignment.Right }, row)
	end
	newLabel({ Name = "Status", Size = UDim2.fromScale(1, 0.06), Position = UDim2.fromScale(0, 0.93), Text = "Loading...", TextColor3 = Color3.fromRGB(170, 170, 190) }, gui)

	-- How-to-play sign
	local signPos = center + Vector3.new(0, 8, -size / 2 + 4)
	local sign = newPart("Part", {
		Name = "HowToPlay",
		Size = Vector3.new(26, 13, 1),
		CFrame = CFrame.lookAt(signPos, Vector3.new(center.X, signPos.Y, center.Z)),
		Color = COLORS.Board,
	}, lobby)
	local signGui = newSurfaceGui(sign, Enum.NormalId.Front)
	newLabel({ Size = UDim2.fromScale(1, 0.2), Text = "HOW TO PLAY", TextColor3 = COLORS.Gold }, signGui)
	newLabel({
		Size = UDim2.fromScale(0.9, 0.72),
		Position = UDim2.fromScale(0.05, 0.24),
		Text = "Races start automatically — just wait here!\n"
			.. "Orange pads give you a speed boost.\n"
			.. "Hold DRIFT while turning, let go for a mini-turbo.\n"
			.. "Fall off? You respawn at the last checkpoint.",
	}, signGui)

	lobby.Parent = workspace
	return lobby
end

------------------------------------------------------------------------
-- KART BUILDER
------------------------------------------------------------------------
local function setupCollisionGroups()
	pcall(function()
		PhysicsService:RegisterCollisionGroup("Karts")
		PhysicsService:RegisterCollisionGroup("Racers")
	end)
	-- Karts and characters pass through each other. Bumping between karts
	-- that are simulated on different players' devices is laggy and glitchy,
	-- and "ghost" karts also stop people from griefing each other.
	PhysicsService:CollisionGroupSetCollidable("Karts", "Karts", false)
	PhysicsService:CollisionGroupSetCollidable("Karts", "Racers", false)
	PhysicsService:CollisionGroupSetCollidable("Racers", "Racers", false)
end

local function buildKart(color: Color3, cframe: CFrame): (Model, BasePart, VehicleSeat)
	local kart = Instance.new("Model")
	kart.Name = "Kart"
	kart.ModelStreamingMode = Enum.ModelStreamingMode.Atomic

	-- The invisible box that actually touches the road. Zero friction because
	-- the client script controls speed directly.
	local hitbox = Instance.new("Part")
	hitbox.Name = "Hitbox"
	hitbox.Size = Vector3.new(5, 2, 7)
	hitbox.Transparency = 1
	hitbox.CFrame = cframe
	hitbox.Anchored = true -- frozen until GO!
	hitbox.CustomPhysicalProperties = PhysicalProperties.new(1, 0, 0, 100, 100)
	hitbox.CollisionGroup = "Karts"
	hitbox.Parent = kart
	kart.PrimaryPart = hitbox

	local function piece(size: Vector3, offset: CFrame, pieceColor: Color3, cylinder: boolean?): BasePart
		local p = Instance.new("Part")
		if cylinder then
			p.Shape = Enum.PartType.Cylinder
		end
		p.Size = size
		p.CFrame = cframe * offset
		p.Color = pieceColor
		p.Material = Enum.Material.SmoothPlastic
		p.TopSurface = Enum.SurfaceType.Smooth
		p.BottomSurface = Enum.SurfaceType.Smooth
		p.CanCollide = false
		p.CanQuery = false
		p.CanTouch = false
		p.Massless = true
		p.CollisionGroup = "Karts"
		local weld = Instance.new("WeldConstraint")
		weld.Part0 = hitbox
		weld.Part1 = p
		weld.Parent = p
		p.Parent = kart
		return p
	end

	-- Front of the kart is -Z (the way it faces)
	piece(Vector3.new(4.4, 0.9, 6.4), CFrame.new(0, -0.2, 0), color) -- body
	piece(Vector3.new(3.2, 0.7, 1.8), CFrame.new(0, 0.35, -2.1), color) -- hood
	piece(Vector3.new(4.8, 0.6, 0.8), CFrame.new(0, -0.45, -3.4), COLORS.Dark) -- front bumper
	piece(Vector3.new(4.6, 0.25, 1.1), CFrame.new(0, 1.35, 3.1), color) -- spoiler
	piece(Vector3.new(0.3, 1.2, 0.3), CFrame.new(-1.6, 0.75, 3.1), COLORS.Dark)
	piece(Vector3.new(0.3, 1.2, 0.3), CFrame.new(1.6, 0.75, 3.1), COLORS.Dark)
	piece(Vector3.new(0.6, 0.6, 0.6), CFrame.new(0, -0.1, 3.4), COLORS.Dark) -- exhaust
	piece(Vector3.new(0.2, 1.1, 1.1), CFrame.new(0, 0.9, -0.8) * CFrame.Angles(math.rad(35), math.rad(90), 0), COLORS.Dark, true) -- steering wheel
	for _, x in { -2.35, 2.35 } do
		for _, z in { -2.3, 2.3 } do
			piece(Vector3.new(1, 1.8, 1.8), CFrame.new(x, -0.1, z), COLORS.Black, true) -- wheels
		end
	end

	local seat = Instance.new("VehicleSeat")
	seat.Name = "DriverSeat"
	seat.Size = Vector3.new(2, 0.5, 2)
	seat.CFrame = cframe * CFrame.new(0, 0.5, 0.8)
	seat.Color = COLORS.Dark
	seat.TopSurface = Enum.SurfaceType.Smooth
	seat.HeadsUpDisplay = false
	seat.CanCollide = false
	seat.Massless = true
	seat.CollisionGroup = "Karts"
	seat:SetAttribute("KartSeat", true)
	local seatWeld = Instance.new("WeldConstraint")
	seatWeld.Part0 = hitbox
	seatWeld.Part1 = seat
	seatWeld.Parent = seat
	seat.Parent = kart

	-- Keeps the kart upright; the client script points it where it should face.
	local center = Instance.new("Attachment")
	center.Name = "Center"
	center.Parent = hitbox
	local align = Instance.new("AlignOrientation")
	align.Name = "KartAlign"
	align.Mode = Enum.OrientationAlignmentMode.OneAttachment
	align.Attachment0 = center
	align.Responsiveness = 25
	align.MaxTorque = math.huge
	align.CFrame = cframe.Rotation
	align.Parent = hitbox

	-- Attachment points for drift sparks / boost flames (the client adds the effects)
	local effectPoints: { [string]: Vector3 } = {
		RearLeft = Vector3.new(-2.35, -1, 2.6),
		RearRight = Vector3.new(2.35, -1, 2.6),
		Exhaust = Vector3.new(0, -0.1, 3.7),
	}
	for name, offset in effectPoints do
		local att = Instance.new("Attachment")
		att.Name = name
		att.Position = offset
		att.Parent = hitbox
	end

	return kart, hitbox, seat
end

------------------------------------------------------------------------
-- WORLD SETUP
------------------------------------------------------------------------
setupCollisionGroups()

local trackFolder: Instance = workspace:FindFirstChild("RaceTrack") or buildTrack()
local lobbyFolder: Instance = workspace:FindFirstChild("RaceLobby") or buildLobby()

-- Remove any other spawn points (like the default one) so everyone spawns in the lobby
for _, descendant in workspace:GetDescendants() do
	if descendant:IsA("SpawnLocation") and not descendant:IsDescendantOf(lobbyFolder) then
		descendant:Destroy()
	end
end

local kartsFolder = newFolder("Karts", workspace)

local function getKillY(): number
	local value = trackFolder:GetAttribute("KillY")
	return if typeof(value) == "number" then value else -math.huge
end

local function sortedByNumber(folder: Instance?): { BasePart }
	local list: { BasePart } = {}
	if not folder then
		return list
	end
	for _, child in folder:GetChildren() do
		if child:IsA("BasePart") and tonumber(child.Name) then
			table.insert(list, child)
		end
	end
	table.sort(list, function(a, b)
		return (tonumber(a.Name) or 0) < (tonumber(b.Name) or 0)
	end)
	return list
end

------------------------------------------------------------------------
-- LEADERBOARD (DataStore)
------------------------------------------------------------------------
local winsStore: OrderedDataStore? = nil
do
	local ok, result = pcall(function()
		return DataStoreService:GetOrderedDataStore(SETTINGS.DATASTORE_NAME)
	end)
	if ok then
		winsStore = result
	else
		warn("[RaceServer] DataStores unavailable:", result)
	end
end

local nameCache: { [number]: string } = {}
local function getName(userId: number): string
	local cached = nameCache[userId]
	if cached then
		return cached
	end
	local ok, name = pcall(function()
		return Players:GetNameFromUserIdAsync(userId)
	end)
	local result = if ok and name then name else ("Player " .. userId)
	nameCache[userId] = result
	return result
end

local function setBoard(rows: { { name: string, wins: number } }?, status: string)
	local board = lobbyFolder:FindFirstChild("LeaderboardBoard")
	local gui = board and board:FindFirstChild("Leaderboard")
	local list = gui and gui:FindFirstChild("List")
	if not (gui and list) then
		return
	end
	local statusLabel = gui:FindFirstChild("Status") :: TextLabel?
	if statusLabel then
		statusLabel.Text = status
	end
	for rank = 1, SETTINGS.LEADERBOARD_SIZE do
		local row = list:FindFirstChild("Row" .. rank)
		if not row then
			continue
		end
		local nameLabel = row:FindFirstChild("PlayerName") :: TextLabel?
		local winsLabel = row:FindFirstChild("Wins") :: TextLabel?
		local entry = rows and rows[rank]
		if nameLabel then
			nameLabel.Text = if entry then entry.name else "—"
		end
		if winsLabel then
			winsLabel.Text = if entry then (entry.wins .. (if entry.wins == 1 then " win" else " wins")) else ""
		end
	end
end

local refreshing = false
local function refreshLeaderboard()
	if refreshing then
		return
	end
	refreshing = true
	local store = winsStore
	if not store then
		setBoard(nil, "Leaderboard offline (see the Output window)")
	else
		local ok, pages = pcall(function()
			return store:GetSortedAsync(false, SETTINGS.LEADERBOARD_SIZE)
		end)
		if ok and pages then
			local rows = {}
			for rank, entry in pages:GetCurrentPage() do
				rows[rank] = { name = getName(tonumber(entry.key) or 0), wins = entry.value }
			end
			setBoard(rows, if #rows == 0 then "No winners yet — be the first!" else "Updates every minute")
		else
			setBoard(nil, "Leaderboard offline (see the Output window)")
			warn(
				"[RaceServer] Couldn't load the leaderboard:",
				pages,
				"\nTesting in Studio? Publish the game, then turn on Game Settings > Security > 'Enable Studio Access to API Services'."
			)
		end
	end
	refreshing = false
end

local function awardWin(player: Player)
	local leaderstats = player:FindFirstChild("leaderstats")
	local wins = leaderstats and leaderstats:FindFirstChild("Wins")
	if wins and wins:IsA("IntValue") then
		wins.Value += 1
	end
	local store = winsStore
	-- Studio test players have negative ids; don't put them on the real board
	if not store or player.UserId <= 0 then
		return
	end
	task.spawn(function()
		local ok, err = pcall(function()
			store:IncrementAsync(tostring(player.UserId), 1)
		end)
		if not ok then
			warn("[RaceServer] Couldn't save win for", player.Name, err)
		end
		task.wait(2)
		refreshLeaderboard()
	end)
end

------------------------------------------------------------------------
-- RACERS
------------------------------------------------------------------------
type Racer = {
	player: Player,
	kart: Model,
	hitbox: BasePart,
	seat: VehicleSeat,
	humanoid: Humanoid,
	nextCheckpoint: number,
	respawnCFrame: CFrame,
	progress: number,
	finished: boolean,
	place: number?,
	finishTime: number?,
	returned: boolean,
	lastRespawn: number,
	connections: { RBXScriptConnection },
}

local racers: { [Player]: Racer } = {}

local function setPhase(phase: string)
	raceState:SetAttribute("Phase", phase)
end

-- Players standing in the lobby, alive, and not already in a race
local function getLobbyPlayers(): { Player }
	local list = {}
	for _, player in Players:GetPlayers() do
		if racers[player] then
			continue
		end
		local character = player.Character
		if not character or not character:FindFirstChild("HumanoidRootPart") then
			continue
		end
		local humanoid = character:FindFirstChildOfClass("Humanoid")
		if humanoid and humanoid.Health > 0 then
			table.insert(list, player)
		end
	end
	return list
end

-- Gives the player a fresh character at the lobby spawn
local function respawnInLobby(player: Player)
	local ok = pcall(function()
		player:LoadCharacterAsync()
	end)
	if not ok and player.Parent == Players then
		player:LoadCharacter() -- older name for the same thing
	end
end

-- Removes a racer's kart and (optionally) sends them back to the lobby
local function releaseRacer(racer: Racer, sendToLobby: boolean)
	if racer.returned then
		return
	end
	racer.returned = true
	for _, connection in racer.connections do
		connection:Disconnect()
	end
	table.clear(racer.connections)
	racer.kart:Destroy()

	local player = racer.player
	player:SetAttribute("Racing", false)
	player:SetAttribute("Finished", false)
	player:SetAttribute("Place", nil)
	if sendToLobby and player.Parent == Players then
		task.spawn(respawnInLobby, player)
	end
end

local function seatDriver(racer: Racer)
	local character = racer.player.Character
	if not character or racer.humanoid.Health <= 0 or racer.seat.Occupant == racer.humanoid then
		return
	end
	character:PivotTo(racer.seat.CFrame * CFrame.new(0, 3, 0))
	racer.seat:Sit(racer.humanoid)
end

local function respawnRacer(racer: Racer, fell: boolean)
	if racer.finished or racer.returned or raceState:GetAttribute("Phase") ~= "Racing" then
		return
	end
	local now = os.clock()
	local cooldown = if fell then 0.75 else SETTINGS.RESPAWN_COOLDOWN
	if now - racer.lastRespawn < cooldown then
		return
	end
	racer.lastRespawn = now
	local target = racer.respawnCFrame + Vector3.new(0, 2.5, 0)
	racer.kart:PivotTo(target)
	racer.hitbox.AssemblyLinearVelocity = Vector3.zero
	racer.hitbox.AssemblyAngularVelocity = Vector3.zero
	raceEvent:FireClient(racer.player, "Respawned", target)
	seatDriver(racer)
end

local function addRacer(player: Player, gridIndex: number, slot: BasePart): Racer?
	local character = player.Character
	if not character then
		return nil
	end
	local humanoid = character:FindFirstChildOfClass("Humanoid")
	if not humanoid or humanoid.Health <= 0 then
		return nil
	end

	local color = KART_COLORS[(gridIndex - 1) % #KART_COLORS + 1]
	local kart, hitbox, seat = buildKart(color, slot.CFrame + Vector3.new(0, 1.1, 0))
	kart.Name = player.Name .. "_Kart"
	kart:SetAttribute("OwnerUserId", player.UserId)
	kart.Parent = kartsFolder

	humanoid.JumpPower = 0 -- jumping would pop them out of the seat
	humanoid.JumpHeight = 0

	local racer: Racer = {
		player = player,
		kart = kart,
		hitbox = hitbox,
		seat = seat,
		humanoid = humanoid,
		nextCheckpoint = 1,
		respawnCFrame = slot.CFrame,
		progress = 0,
		finished = false,
		place = nil,
		finishTime = nil,
		returned = false,
		lastRespawn = 0,
		connections = {},
	}
	racers[player] = racer
	seatDriver(racer)

	player:SetAttribute("Racing", true)
	player:SetAttribute("Finished", false)
	player:SetAttribute("Place", gridIndex)

	-- If they somehow get out of the kart, put them back in
	table.insert(racer.connections, seat:GetPropertyChangedSignal("Occupant"):Connect(function()
		if seat.Occupant == nil and not racer.finished and not racer.returned then
			task.delay(0.3, function()
				if not racer.returned then
					seatDriver(racer)
				end
			end)
		end
	end))
	-- Died or reset: out of this race, they'll respawn in the lobby automatically
	table.insert(racer.connections, humanoid.Died:Connect(function()
		releaseRacer(racer, false)
	end))
	table.insert(racer.connections, player.CharacterRemoving:Connect(function()
		releaseRacer(racer, false)
	end))
	return racer
end

local function passedCheckpoint(checkpoint: BasePart, pos: Vector3): boolean
	local rel = checkpoint.CFrame:PointToObjectSpace(pos) -- negative Z = in front of the gate
	local half = checkpoint.Size / 2
	return rel.Z <= 0 and rel.Z > -60 and math.abs(rel.X) <= half.X and math.abs(rel.Y) <= half.Y
end

local function shuffle(list: { any })
	for i = #list, 2, -1 do
		local j = math.random(1, i)
		list[i], list[j] = list[j], list[i]
	end
end

------------------------------------------------------------------------
-- THE RACE
------------------------------------------------------------------------
local function runRace()
	local checkpoints = sortedByNumber(trackFolder:FindFirstChild("Checkpoints"))
	local slots = sortedByNumber(trackFolder:FindFirstChild("StartSlots"))
	local startLine = trackFolder:FindFirstChild("StartLine") :: BasePart?
	if #checkpoints == 0 or #slots == 0 or not startLine then
		warn("[RaceServer] RaceTrack is missing Checkpoints, StartSlots or StartLine")
		task.wait(5)
		return
	end
	local killY = getKillY()

	-- 1) Put everyone from the lobby into a kart on the grid
	local entrants = getLobbyPlayers()
	shuffle(entrants)
	table.clear(racers)
	local startedCount = 0
	for _, player in entrants do
		if startedCount >= math.min(SETTINGS.MAX_RACERS, #slots) then
			break
		end
		if addRacer(player, startedCount + 1, slots[startedCount + 1]) then
			startedCount += 1
		end
	end
	if startedCount == 0 then
		return
	end
	raceState:SetAttribute("RacerCount", startedCount)

	-- 2) Countdown
	raceState:SetAttribute("Countdown", 0)
	setPhase("Countdown")
	task.wait(1)
	for n = SETTINGS.COUNTDOWN_TIME, 1, -1 do
		raceState:SetAttribute("Countdown", n)
		for _, racer in racers do
			if not racer.returned then
				seatDriver(racer)
			end
		end
		task.wait(1)
	end

	-- 3) GO! Unfreeze the karts and hand each one's physics to its driver,
	--    so driving feels instant on their screen.
	local raceStart = workspace:GetServerTimeNow()
	local deadline = raceStart + SETTINGS.RACE_TIME_LIMIT
	raceState:SetAttribute("RaceStart", raceStart)
	raceState:SetAttribute("RaceEnd", deadline)
	for player, racer in racers do
		if not racer.returned then
			racer.hitbox.Anchored = false
			pcall(function()
				racer.hitbox:SetNetworkOwner(player)
			end)
		end
	end
	setPhase("Racing")

	-- 4) Track progress every frame until everyone is done or time runs out
	local finishedCount = 0
	while true do
		RunService.Heartbeat:Wait()
		local now = workspace:GetServerTimeNow()
		local stillRacing = 0

		for player, racer in racers do
			if racer.returned or racer.finished then
				continue
			end
			stillRacing += 1
			local pos = racer.hitbox.Position

			if pos.Y < killY then
				respawnRacer(racer, true)
				continue
			end

			-- Passed the next gate? (also checks the one after, in case a lag spike skipped one)
			local index = racer.nextCheckpoint
			local passed = nil
			if checkpoints[index] and passedCheckpoint(checkpoints[index], pos) then
				passed = index
			elseif checkpoints[index + 1] and passedCheckpoint(checkpoints[index + 1], pos) then
				passed = index + 1
			end
			if passed then
				racer.nextCheckpoint = passed + 1
				racer.respawnCFrame = flatCFrame(checkpoints[passed].Position, checkpoints[passed].CFrame.LookVector)
			end

			if racer.nextCheckpoint > #checkpoints then
				-- Crossed the finish line
				finishedCount += 1
				racer.finished = true
				racer.place = finishedCount
				racer.finishTime = now - raceStart
				player:SetAttribute("Finished", true)
				player:SetAttribute("Place", finishedCount)
				raceEvent:FireAllClients("RacerFinished", player.UserId, player.DisplayName, finishedCount, racer.finishTime)

				if finishedCount == 1 then
					if now + SETTINGS.TIME_AFTER_FIRST_FINISH < deadline then
						deadline = now + SETTINGS.TIME_AFTER_FIRST_FINISH
						raceState:SetAttribute("RaceEnd", deadline)
					end
					if startedCount >= SETTINGS.MIN_RACERS_FOR_WIN then
						awardWin(player)
					end
				end
				task.delay(SETTINGS.RETURN_DELAY, function()
					releaseRacer(racer, true)
				end)
			else
				-- How far along the track they are, for live 1st/2nd/3rd...
				local target = checkpoints[racer.nextCheckpoint].Position
				local previous = if racer.nextCheckpoint == 1 then startLine.Position else checkpoints[racer.nextCheckpoint - 1].Position
				local segment = math.max((target - previous).Magnitude, 1)
				local fraction = 1 - math.clamp((target - pos).Magnitude / segment, 0, 1)
				racer.progress = (racer.nextCheckpoint - 1) + fraction
			end
		end

		-- Live positions for everyone still driving
		local order: { Racer } = {}
		for _, racer in racers do
			if not racer.finished and not racer.returned then
				table.insert(order, racer)
			end
		end
		table.sort(order, function(a, b)
			return a.progress > b.progress
		end)
		for rank, racer in order do
			local place = finishedCount + rank
			if racer.player:GetAttribute("Place") ~= place then
				racer.player:SetAttribute("Place", place)
			end
		end

		if stillRacing == 0 or now >= deadline then
			break
		end
	end

	-- 5) Race over
	local anyoneOnTrack = false
	for _, racer in racers do
		if not racer.returned then
			anyoneOnTrack = true
			if not racer.finished then
				raceEvent:FireClient(racer.player, "TimeUp")
			end
		end
	end
	setPhase("Results")
	if anyoneOnTrack then
		task.wait(SETTINGS.RETURN_DELAY)
	end

	local results = {}
	for _, racer in racers do
		table.insert(results, { name = racer.player.DisplayName, place = racer.place, time = racer.finishTime })
	end
	table.sort(results, function(a, b)
		if a.place and b.place then
			return a.place < b.place
		elseif a.place then
			return true
		elseif b.place then
			return false
		end
		return a.name < b.name
	end)
	for _, racer in racers do
		releaseRacer(racer, true)
	end
	raceEvent:FireAllClients("Results", results)
	table.clear(racers)
end

------------------------------------------------------------------------
-- PLAYERS
------------------------------------------------------------------------
local function onCharacterAdded(character: Model)
	local function setGroup(descendant: Instance)
		if descendant:IsA("BasePart") then
			descendant.CollisionGroup = "Racers"
		end
	end
	for _, descendant in character:GetDescendants() do
		setGroup(descendant)
	end
	character.DescendantAdded:Connect(setGroup)
end

local function onPlayerAdded(player: Player)
	local leaderstats = Instance.new("Folder")
	leaderstats.Name = "leaderstats" -- this exact name shows stats in the player list
	local wins = Instance.new("IntValue")
	wins.Name = "Wins"
	wins.Parent = leaderstats
	leaderstats.Parent = player

	player.CharacterAdded:Connect(onCharacterAdded)
	if player.Character then
		onCharacterAdded(player.Character)
	end

	local store = winsStore
	if store and player.UserId > 0 then
		task.spawn(function()
			local ok, value = pcall(function()
				return (store:GetAsync(tostring(player.UserId)))
			end)
			if ok and typeof(value) == "number" then
				wins.Value += value
			end
		end)
	end
end

Players.PlayerAdded:Connect(onPlayerAdded)
for _, player in Players:GetPlayers() do
	onPlayerAdded(player)
	if player.Character then
		task.spawn(respawnInLobby, player) -- anyone who spawned before the lobby existed
	end
end

Players.PlayerRemoving:Connect(function(player)
	local racer = racers[player]
	if racer then
		releaseRacer(racer, false)
	end
end)

raceEvent.OnServerEvent:Connect(function(player, action)
	if action == "Respawn" then
		local racer = racers[player]
		if racer and not racer.returned then
			respawnRacer(racer, racer.hitbox.Position.Y < getKillY())
		end
	end
end)

task.spawn(function()
	while true do
		refreshLeaderboard()
		task.wait(SETTINGS.LEADERBOARD_REFRESH)
	end
end)

------------------------------------------------------------------------
-- MAIN LOOP
------------------------------------------------------------------------
while true do
	setPhase("Waiting")
	while #getLobbyPlayers() < SETTINGS.MIN_PLAYERS_TO_START do
		task.wait(1)
	end

	setPhase("Intermission")
	local cancelled = false
	for t = SETTINGS.INTERMISSION_TIME, 1, -1 do
		raceState:SetAttribute("Countdown", t)
		task.wait(1)
		if #getLobbyPlayers() < SETTINGS.MIN_PLAYERS_TO_START then
			cancelled = true
			break
		end
	end

	if not cancelled then
		local ok, err = pcall(runRace)
		if not ok then
			warn("[RaceServer] Race crashed:", err)
			for _, racer in racers do
				releaseRacer(racer, true)
			end
			table.clear(racers)
		end
	end
end
