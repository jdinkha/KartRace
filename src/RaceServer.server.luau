--[[
	RaceServer  —  a normal Script that goes in ServerScriptService

	Kart racing MVP, server side. This script:
	  • builds the lobby, one linear race track and some sky scenery out of parts when the game starts
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
local Lighting = game:GetService("Lighting")

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
	WALL_THICKNESS = 1.5,
	STEP = 10, -- length of each road piece (smaller = smoother but more parts)
	PRE_START = 80, -- road behind the start line (room for the starting grid)
	RUN_OFF = 70, -- road after the finish line
	CHECKPOINT_SPACING = 100,
	MAX_BANK = 12, -- degrees the road leans into corners, like a real race track (0 = flat)
	BANK_RADIUS = 100, -- corners this tight (or tighter) get the full lean
	RAMP_ANGLE = 16, -- how steep the jump ramp is at its lip, in degrees
	ARCH_SPACING = 260, -- gap between the glowing arches over the road (0 = no arches)
	SCENERY_SEED = 7, -- change this number to shuffle the floating islands around

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
	-- Kinds: "Boost" (speed pad), "Ramp" (jump), "Banner" (arch with `text` on it)
	FEATURES = {
		{ kind = "Boost", point = 3, lane = 0 },
		{ kind = "Boost", point = 13, lane = -8 },
		{ kind = "Banner", point = 19, text = "BIG JUMP AHEAD!" },
		{ kind = "Boost", point = 19, lane = -9 },
		{ kind = "Boost", point = 19, lane = 9 },
		{ kind = "Ramp", point = 20, lane = 0 },
		{ kind = "Boost", point = 27, lane = 8 },
		{ kind = "Boost", point = 30, lane = 0 },
	},
}

------------------------------------------------------------------------
-- LOBBY  —  the floating island players wait on between races
------------------------------------------------------------------------
local LOBBY = {
	RADIUS = 56, -- size of the island
	BOUNCE_POWER = 110, -- how high the bounce pads launch you
	SHOWROOM_SPIN = 30, -- degrees per second the display karts turn
}

local COLORS = {
	Road = Color3.fromRGB(58, 58, 66),
	CurbA = Color3.fromRGB(225, 45, 45),
	CurbB = Color3.fromRGB(245, 245, 245),
	Wall = Color3.fromRGB(60, 140, 255),
	WallStripe = Color3.fromRGB(245, 245, 245),
	Pillar = Color3.fromRGB(150, 150, 160),
	Boost = Color3.fromRGB(255, 120, 20),
	BoostArrow = Color3.fromRGB(255, 235, 90),
	Ramp = Color3.fromRGB(255, 210, 40),
	RampStripe = Color3.fromRGB(40, 40, 48),
	LobbyFloor = Color3.fromRGB(110, 200, 120),
	Plaza = Color3.fromRGB(225, 220, 205),
	Dirt = Color3.fromRGB(120, 85, 55),
	Rock = Color3.fromRGB(110, 105, 115),
	Trunk = Color3.fromRGB(110, 75, 45),
	Board = Color3.fromRGB(25, 25, 40),
	Gold = Color3.fromRGB(255, 215, 70),
	Silver = Color3.fromRGB(205, 210, 220),
	Bronze = Color3.fromRGB(215, 140, 80),
	White = Color3.fromRGB(245, 245, 245),
	Black = Color3.fromRGB(25, 25, 25),
	Dark = Color3.fromRGB(35, 35, 40),
	LightOff = Color3.fromRGB(45, 45, 50),
	LightRed = Color3.fromRGB(255, 40, 40),
	LightGreen = Color3.fromRGB(60, 255, 90),
}

-- The glowing arches over the track cycle through these
local RAINBOW = {
	Color3.fromRGB(255, 70, 70),
	Color3.fromRGB(255, 160, 40),
	Color3.fromRGB(255, 230, 60),
	Color3.fromRGB(80, 230, 100),
	Color3.fromRGB(60, 180, 255),
	Color3.fromRGB(170, 90, 255),
}

local LEAF_COLORS = {
	Color3.fromRGB(70, 170, 70),
	Color3.fromRGB(95, 195, 80),
	Color3.fromRGB(60, 150, 90),
	Color3.fromRGB(255, 160, 200), -- blossom
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
	if props.Shape then
		(part :: any).Shape = props.Shape -- set first: changing Shape can reset Size
	end
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

-- Cylinder parts lie on their side; this stands one up (round face on top)
local function upright(cf: CFrame): CFrame
	return cf * CFrame.Angles(0, 0, math.rad(90))
end

-- A flat triangle a-b-c made from two WedgeParts, `thickness` deep below the
-- triangle. Neighbouring triangles share exact edges, so a road built from
-- them has no steps or overlapping lips for karts to catch on.
local function buildTriangle(a: Vector3, b: Vector3, c: Vector3, thickness: number, props: { [string]: any }, parent: Instance)
	-- Rename the corners so b-c is the longest edge (then `a` sits right above it)
	local ab, ac, bc = b - a, c - a, c - b
	local abd, acd, bcd = ab:Dot(ab), ac:Dot(ac), bc:Dot(bc)
	if abd > acd and abd > bcd then
		a, c = c, a
	elseif acd > bcd and acd > abd then
		a, b = b, a
	end
	ab, ac, bc = b - a, c - a, c - b

	local normal = ac:Cross(ab)
	if normal.Magnitude < 1e-4 then
		return -- squashed flat, nothing to draw
	end
	normal = normal.Unit
	local up = bc:Cross(normal).Unit
	local back = bc.Unit
	local height = math.abs(ab:Dot(up))
	-- shift both wedges down so their top faces sit exactly on the triangle
	local sink = (if normal.Y >= 0 then normal else -normal) * (thickness / 2)

	for _, half in {
		{ center = (a + b) / 2, depth = math.abs(ab:Dot(back)), x = normal, z = back },
		{ center = (a + c) / 2, depth = math.abs(ac:Dot(back)), x = -normal, z = -back },
	} do
		if half.depth < 0.01 or height < 0.01 then
			continue
		end
		local wedge = table.clone(props)
		wedge.Size = Vector3.new(thickness, height, half.depth)
		wedge.CFrame = CFrame.fromMatrix(half.center - sink, half.x, up, half.z)
		newPart("WedgePart", wedge, parent)
	end
end

local function buildTree(base: Vector3, scale: number, leafColor: Color3, parent: Instance, solidTrunk: boolean)
	local trunkHeight = 7 * scale
	local trunk = {
		Name = "TreeTrunk",
		Shape = Enum.PartType.Cylinder,
		Size = Vector3.new(trunkHeight, 1.6 * scale, 1.6 * scale),
		CFrame = upright(CFrame.new(base + Vector3.new(0, trunkHeight / 2, 0))),
		Color = COLORS.Trunk,
		Material = Enum.Material.Wood,
	}
	newPart("Part", if solidTrunk then trunk else ghost(trunk), parent)
	newPart("Part", ghost({
		Name = "TreeLeaves",
		Shape = Enum.PartType.Ball,
		Size = Vector3.one * (8 * scale),
		CFrame = CFrame.new(base + Vector3.new(0, trunkHeight + 1.5 * scale, 0)),
		Color = leafColor,
		Material = Enum.Material.Grass,
	}), parent)
	newPart("Part", ghost({
		Name = "TreeLeaves",
		Shape = Enum.PartType.Ball,
		Size = Vector3.one * (5.5 * scale),
		CFrame = CFrame.new(base + Vector3.new(1.6 * scale, trunkHeight + 4.6 * scale, 0.8 * scale)),
		Color = leafColor,
		Material = Enum.Material.Grass,
	}), parent)
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

-- Two posts and a banner across the road. `cf` = centre of the road, facing along it.
local function buildArch(cf: CFrame, text: string, parent: Instance)
	local width = TRACK.ROAD_WIDTH
	for _, side in { -1, 1 } do
		newPart("Part", {
			Name = "ArchPost",
			Size = Vector3.new(2, 18, 2),
			CFrame = cf * CFrame.new(side * (width / 2 + TRACK.WALL_THICKNESS + 1), 9, 0),
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

-- Countdown lights hanging under the START banner (the race loop switches them on)
local function buildStartLights(cf: CFrame, parent: Instance)
	local folder = newFolder("StartLights", parent)
	local count = SETTINGS.COUNTDOWN_TIME
	newPart("Part", ghost({
		Name = "LightBar",
		Size = Vector3.new(count * 4 + 2, 0.6, 0.6),
		CFrame = cf * CFrame.new(0, 14.7, 0),
		Color = COLORS.Dark,
	}), folder)
	for k = 1, count do
		newPart("Part", ghost({
			Name = tostring(k),
			Shape = Enum.PartType.Ball,
			Size = Vector3.new(2.6, 2.6, 2.6),
			CFrame = cf * CFrame.new((k - (count + 1) / 2) * 4, 13.1, 0),
			Color = COLORS.LightOff,
		}), folder)
	end
end

-- A glowing arch over the road
local function buildGate(cf: CFrame, color: Color3, parent: Instance)
	local x = TRACK.ROAD_WIDTH / 2 + TRACK.WALL_THICKNESS + 1.5
	local height = 16
	for _, side in { -1, 1 } do
		newPart("Part", ghost({
			Name = "GatePost",
			Size = Vector3.new(1.6, height, 1.6),
			CFrame = cf * CFrame.new(side * x, height / 2 - 1, 0),
			Color = color,
			Material = Enum.Material.Neon,
		}), parent)
	end
	newPart("Part", ghost({
		Name = "GateBeam",
		Size = Vector3.new(x * 2 + 1.6, 1.6, 1.6),
		CFrame = cf * CFrame.new(0, height - 1.8, 0),
		Color = color,
		Material = Enum.Material.Neon,
	}), parent)
end

local function buildBoostPad(cf: CFrame, road: Instance, decor: Instance)
	local pad = newPart("Part", {
		Name = "BoostPad",
		Size = Vector3.new(10, 0.1, 16),
		CFrame = cf * CFrame.new(0, 0.1, 0),
		Color = COLORS.Boost,
		Material = Enum.Material.Neon,
		CanCollide = false, -- karts drive over it; the client detects it with a raycast
	}, road)
	pad:SetAttribute("BoostPad", true)
	-- three yellow arrows pointing the way to go
	for _, z in { -5.5, -1, 3.5 } do
		for _, side in { -1, 1 } do
			newPart("Part", ghost({
				Name = "BoostArrow",
				Size = Vector3.new(0.9, 0.05, 4.2),
				CFrame = cf * CFrame.new(side * 1.35, 0.175, z + 1.6) * CFrame.Angles(0, math.rad(side * 40), 0),
				Color = COLORS.BoostArrow,
				Material = Enum.Material.Neon,
			}), decor)
		end
	end
end

-- A jump ramp that curves up gradually, so karts glide onto it instead of
-- slamming into a sharp edge. `cf` = where it starts, on the road surface.
local function buildRamp(cf: CFrame, road: Instance, walls: Instance)
	local width = TRACK.ROAD_WIDTH - 2
	local pieces = 5
	local pieceLength = 26 / pieces
	local point = Vector3.zero -- top surface, in the ramp's own space (forward = -Z)
	for k = 1, pieces do
		local angle = math.rad(TRACK.RAMP_ANGLE) * (k - 0.5) / pieces
		local nextPoint = point + Vector3.new(0, math.sin(angle), -math.cos(angle)) * pieceLength
		local mid = (point + nextPoint) / 2
		newPart("Part", {
			Name = "Ramp",
			Size = Vector3.new(width, 1, pieceLength),
			CFrame = cf * CFrame.new(mid) * CFrame.Angles(angle, 0, 0) * CFrame.new(0, -0.5, 0),
			Color = if k % 2 == 1 then COLORS.Ramp else COLORS.RampStripe,
		}, road)
		-- solid block underneath so the ramp isn't hollow
		local fill = point.Y - 0.9
		if fill > 0.3 then
			newPart("Part", {
				Name = "RampSupport",
				Size = Vector3.new(width, fill, math.abs(nextPoint.Z - point.Z)),
				CFrame = cf * CFrame.new(0, fill / 2, mid.Z),
				Color = COLORS.Dark,
			}, walls)
		end
		point = nextPoint
	end
end

-- Arrow board on top of the outside wall, warning that a sharp corner is coming
local function buildCornerSign(frame: CFrame, turnRight: boolean, parent: Instance)
	local side = if turnRight then -1 else 1 -- outside of the corner
	local pos = frame:PointToWorldSpace(Vector3.new(side * (TRACK.ROAD_WIDTH / 2 + TRACK.WALL_THICKNESS / 2), TRACK.WALL_HEIGHT + 1.8, 0))
	local sign = newPart("Part", ghost({
		Name = "CornerSign",
		Size = Vector3.new(9, 3.6, 0.5),
		CFrame = CFrame.lookAt(pos, pos - frame.LookVector, frame.UpVector), -- faces oncoming karts
		Color = COLORS.CurbA,
	}), parent)
	local gui = newSurfaceGui(sign, Enum.NormalId.Front)
	newLabel({ Size = UDim2.fromScale(1, 1), Text = if turnRight then ">>>" else "<<<" }, gui)
end

-- Grandstand full of fans on the left side of the start line
local function buildGrandstand(cf: CFrame, parent: Instance)
	local rng = Random.new(5)
	local length = 70
	local rows = 4
	local depth = 4
	local inner = TRACK.ROAD_WIDTH / 2 + TRACK.WALL_THICKNESS + 4 -- gap between the wall and the front row
	local outer = inner + rows * depth
	newPart("Part", ghost({
		Name = "StandBase",
		Size = Vector3.new(outer - inner + 4, 2, length + 4),
		CFrame = cf * CFrame.new(-(inner + outer) / 2, -2, 0),
		Color = COLORS.Pillar,
		Material = Enum.Material.Concrete,
	}), parent)
	for r = 0, rows - 1 do
		local x = -(inner + depth * (r + 0.5))
		local h = 1 + r * 1.8
		newPart("Part", ghost({
			Name = "StandRow",
			Size = Vector3.new(depth, h, length),
			CFrame = cf * CFrame.new(x, h / 2 - 1, 0),
			Color = if r % 2 == 0 then COLORS.Wall else COLORS.WallStripe,
		}), parent)
		for z = -length / 2 + 1.5, length / 2 - 1.5, 2.6 do
			if rng:NextNumber() < 0.75 then
				local fanHeight = rng:NextNumber(1.8, 2.4)
				newPart("Part", ghost({
					Name = "Fan",
					Size = Vector3.new(1.2, fanHeight, 1.4),
					CFrame = cf * CFrame.new(x + 0.6, h - 1 + fanHeight / 2, z + rng:NextNumber(-0.3, 0.3)),
					Color = KART_COLORS[rng:NextInteger(1, #KART_COLORS)],
				}), parent)
			end
		end
	end
	local roofHeight = 1 + rows * 1.8 + 6
	for _, z in { -length / 2 + 1, length / 2 - 1 } do
		newPart("Part", ghost({
			Name = "StandPost",
			Size = Vector3.new(1, roofHeight, 1),
			CFrame = cf * CFrame.new(-(outer - 0.5), roofHeight / 2 - 1, z),
			Color = COLORS.White,
		}), parent)
	end
	newPart("Part", ghost({
		Name = "StandRoof",
		Size = Vector3.new(outer - inner + 4, 0.8, length + 2),
		CFrame = cf * CFrame.new(-(inner + outer) / 2, roofHeight - 1, 0),
		Color = COLORS.White,
	}), parent)
end

local function buildTrack(): Folder
	local track = Instance.new("Folder")
	track.Name = "RaceTrack"
	local road = newFolder("Road", track) -- surfaces karts drive on (the client's ground sensor only looks in here)
	local walls = newFolder("Walls", track) -- barriers karts bump into
	local decor = newFolder("Decor", track) -- visuals only
	local checkpointFolder = newFolder("Checkpoints", track)
	local slotFolder = newFolder("StartSlots", track)

	local samples, pointToSample = sampleTrack()
	local count = #samples
	local dist = { 0 }
	for i = 2, count do
		dist[i] = dist[i - 1] + (samples[i] - samples[i - 1]).Magnitude
	end
	local total = dist[count]
	local width = TRACK.ROAD_WIDTH
	local halfWidth = width / 2
	local thick = TRACK.WALL_THICKNESS

	-- How sharply the road turns at each sample (+ = right turn, - = left)
	local turnAngle: { number } = table.create(count, 0) -- radians
	local bend: { number } = table.create(count, 0) -- radians per stud
	for i = 2, count - 1 do
		local inDir = samples[i] - samples[i - 1]
		local outDir = samples[i + 1] - samples[i]
		local flatIn = Vector3.new(inDir.X, 0, inDir.Z)
		local flatOut = Vector3.new(outDir.X, 0, outDir.Z)
		if flatIn.Magnitude > 1e-3 and flatOut.Magnitude > 1e-3 then
			local angle = math.asin(math.clamp(-flatIn.Unit:Cross(flatOut.Unit).Y, -1, 1))
			turnAngle[i] = angle
			bend[i] = angle / ((flatIn.Magnitude + flatOut.Magnitude) / 2)
		end
	end

	-- Average the bend over nearby samples so banking and curbs ease in and out,
	-- then make a "frame" at every sample: its position plus which way is
	-- right / up / forward on the (possibly banked) road.
	local corner: { number } = {}
	local frames: { CFrame } = {}
	for i = 1, count do
		local sum, n = 0, 0
		for j = math.max(1, i - 4), math.min(count, i + 4) do
			sum += bend[j]
			n += 1
		end
		corner[i] = sum / n
		local bank = math.rad(TRACK.MAX_BANK) * math.clamp(corner[i] * TRACK.BANK_RADIUS, -1, 1)

		local look = (samples[math.min(i + 1, count)] - samples[math.max(i - 1, 1)]).Unit
		local flatRight = look:Cross(Vector3.yAxis)
		flatRight = if flatRight.Magnitude > 1e-3 then flatRight.Unit else Vector3.xAxis
		local level = flatRight:Cross(look).Unit -- straight up from the road before it leans
		local right = flatRight * math.cos(bank) - level * math.sin(bank)
		local up = level * math.cos(bank) + flatRight * math.sin(bank)
		frames[i] = CFrame.fromMatrix(samples[i], right, up)
	end

	-- Road frame at a given distance along the track
	local function frameAt(d: number): CFrame
		d = math.clamp(d, 0, total)
		for i = 1, count - 1 do
			if dist[i + 1] >= d then
				local segLen = dist[i + 1] - dist[i]
				local alpha = if segLen > 0 then (d - dist[i]) / segLen else 0
				return frames[i]:Lerp(frames[i + 1], alpha)
			end
		end
		return frames[count]
	end

	-- A point on the road at sample i: `x` = sideways from the centre line, `y` = height above the surface
	local function roadPoint(i: number, x: number, y: number?): Vector3
		return frames[i]:PointToWorldSpace(Vector3.new(x, y or 0, 0))
	end

	-- Road surface. Every piece is cut to fit exactly against its neighbours
	-- (two triangles on bends, one block on straights), so there are no
	-- overlapping edges or little steps for karts to snag on.
	local roadProps = { Name = "Road", Color = COLORS.Road, Material = Enum.Material.Asphalt }
	for i = 1, count - 1 do
		local l1, r1 = roadPoint(i, -halfWidth), roadPoint(i, halfWidth)
		local l2, r2 = roadPoint(i + 1, -halfWidth), roadPoint(i + 1, halfWidth)
		local across, along = r1 - l1, l2 - l1
		if along.Magnitude < 0.05 then
			continue
		end
		if ((r2 - l2) - across).Magnitude < 0.01 and math.abs(across.Unit:Dot(along.Unit)) < 0.001 then
			local center = (l1 + r1 + l2 + r2) / 4
			local block = table.clone(roadProps)
			block.Size = Vector3.new(width, 1, along.Magnitude)
			block.CFrame = CFrame.lookAt(center, center + along, across:Cross(along)) * CFrame.new(0, -0.5, 0)
			newPart("Part", block, road)
		else
			buildTriangle(l1, r1, r2, 1, roadProps, road)
			buildTriangle(l1, r2, l2, 1, roadProps, road)
		end
	end

	-- Red & white curbs on corners, thin white lines along the straights
	for i = 1, count - 1 do
		local cornering = math.abs(corner[i]) > 1 / 200 or math.abs(corner[i + 1]) > 1 / 200
		local stripWidth = if cornering then 2.5 else 0.8
		local inset = halfWidth - (if cornering then 1.25 else 1.4)
		local lift = 0.08 + (i % 2) * 0.01 -- neighbours sit at slightly different heights so they don't flicker
		local up = (frames[i].UpVector + frames[i + 1].UpVector).Unit
		for _, side in { -1, 1 } do
			local a, b = roadPoint(i, side * inset, lift), roadPoint(i + 1, side * inset, lift)
			if (b - a).Magnitude < 0.05 then
				continue
			end
			newPart("Part", ghost({
				Name = if cornering then "Curb" else "EdgeLine",
				Size = Vector3.new(stripWidth, 0.1, (b - a).Magnitude + 0.4),
				CFrame = CFrame.lookAt((a + b) / 2, b, up),
				Color = if not cornering then COLORS.White elseif i % 2 == 0 then COLORS.CurbA else COLORS.CurbB,
			}), decor)
		end
	end

	-- Walls. Pieces meet exactly at the road's edge, so the side karts scrape
	-- along is smooth. On the outside of a bend each piece is stretched a touch
	-- so there's no notch at the back.
	local wallTall = TRACK.WALL_HEIGHT + 1 -- also reaches 1 stud below the road so nothing slips underneath
	local function stretch(j: number, side: number): number
		local angle = turnAngle[j]
		if side * angle < 0 then
			return thick * math.tan(math.abs(angle) / 2) + 0.02
		end
		return 0
	end
	for _, side in { -1, 1 } do
		for i = 1, count - 1 do
			local a, b = roadPoint(i, side * halfWidth), roadPoint(i + 1, side * halfWidth)
			local len = (b - a).Magnitude
			if len < 0.05 then
				continue
			end
			local extraBack, extraFront = stretch(i, side), stretch(i + 1, side)
			local up = (frames[i].UpVector + frames[i + 1].UpVector).Unit
			newPart("Part", {
				Name = "Wall",
				Size = Vector3.new(thick, wallTall, len + extraBack + extraFront),
				CFrame = CFrame.lookAt((a + b) / 2, b, up) * CFrame.new(side * thick / 2, wallTall / 2 - 1, (extraBack - extraFront) / 2),
				Color = if math.floor(i / 2) % 2 == 0 then COLORS.Wall else COLORS.WallStripe,
			}, walls)
		end
	end

	-- Support pillars down to the ground
	local minY = math.huge
	for _, p in samples do
		minY = math.min(minY, p.Y)
	end
	for i = 10, count, 20 do
		local pos = samples[i]
		local height = pos.Y - 1.5
		if height > 6 then
			newPart("Part", ghost({
				Name = "Pillar",
				Size = Vector3.new(6, height, 6),
				CFrame = CFrame.new(pos.X, height / 2, pos.Z),
				Color = COLORS.Pillar,
				Material = Enum.Material.Concrete,
			}), decor)
			newPart("Part", ghost({
				Name = "PillarCap",
				Size = Vector3.new(10, 1, 10),
				CFrame = frames[i] * CFrame.new(0, -1.5, 0),
				Color = COLORS.Pillar,
				Material = Enum.Material.Concrete,
			}), decor)
		end
	end

	-- Boost pads, ramps and banners
	local busy: { number } = {} -- spots where a glowing arch would get in the way
	for _, feature in TRACK.FEATURES do
		local index = pointToSample[feature.point]
		if not index then
			continue
		end
		local d = dist[index]
		local frame = frameAt(d)
		if feature.kind == "Boost" then
			buildBoostPad(frame * CFrame.new(feature.lane or 0, 0, 0), road, decor)
		elseif feature.kind == "Ramp" then
			buildRamp(frame * CFrame.new(feature.lane or 0, 0, 0), road, walls)
			table.insert(busy, d)
		elseif feature.kind == "Banner" then
			buildArch(frame, feature.text or "", decor)
			table.insert(busy, d)
		end
	end

	-- Start line, finish line, arches and end walls
	local startDist = TRACK.PRE_START
	local finishDist = total - TRACK.RUN_OFF
	table.insert(busy, startDist)
	table.insert(busy, finishDist)

	local startFrame = frameAt(startDist)
	local startCF = flatCFrame(startFrame.Position, startFrame.LookVector)
	newPart("Part", ghost({
		Name = "StartLine",
		Size = Vector3.new(width, 0.1, 2),
		CFrame = startFrame * CFrame.new(0, 0.1, 0),
		Color = COLORS.White,
	}), track)
	buildArch(startCF, "START", decor)
	buildStartLights(startCF, track)
	buildGrandstand(startCF, decor)

	local finishFrame = frameAt(finishDist)
	local tiles = 12
	local tileWidth = width / tiles
	for row = 0, 1 do
		for col = 0, tiles - 1 do
			newPart("Part", ghost({
				Name = "FinishTile",
				Size = Vector3.new(tileWidth, 0.1, 2),
				CFrame = finishFrame * CFrame.new(-width / 2 + tileWidth * (col + 0.5), 0.1, (row - 0.5) * 2),
				Color = if (row + col) % 2 == 0 then COLORS.Black else COLORS.White,
			}), decor)
		end
	end
	buildArch(flatCFrame(finishFrame.Position, finishFrame.LookVector), "FINISH", decor)

	local endHeight = TRACK.WALL_HEIGHT + 4
	newPart("Part", {
		Name = "EndWall",
		Size = Vector3.new(width + thick * 2, endHeight, 2),
		CFrame = flatCFrame(samples[count], frames[count].LookVector) * CFrame.new(0, endHeight / 2 - 1, 1),
		Color = COLORS.Wall,
	}, walls)
	newPart("Part", {
		Name = "BackWall",
		Size = Vector3.new(width + thick * 2, endHeight, 2),
		CFrame = flatCFrame(samples[1], frames[1].LookVector) * CFrame.new(0, endHeight / 2 - 1, 1),
		Color = COLORS.Wall,
	}, walls)

	-- Glowing rainbow arches every so often (skipping spots that already have something)
	if TRACK.ARCH_SPACING > 0 then
		local gateCount = 0
		local d = startDist + TRACK.ARCH_SPACING
		while d < finishDist - 40 do
			local clear = true
			for _, spot in busy do
				if math.abs(d - spot) < 60 then
					clear = false
					break
				end
			end
			if clear then
				gateCount += 1
				buildGate(frameAt(d), RAINBOW[(gateCount - 1) % #RAINBOW + 1], decor)
			end
			d += TRACK.ARCH_SPACING
		end
	end

	-- Arrow signs before the sharpest corners
	local lastSign = -math.huge
	for i = 1, count do
		if math.abs(corner[i]) > 1 / 150 and i - lastSign > 15 and dist[i] > startDist and dist[i] < finishDist then
			lastSign = i
			buildCornerSign(frames[math.max(1, i - 2)], corner[i] > 0, decor)
		end
	end

	-- Invisible checkpoint "gates". Racers must pass them in order; the last one is the finish.
	local raceLength = finishDist - startDist
	local gates = math.max(1, math.floor(raceLength / TRACK.CHECKPOINT_SPACING))
	for k = 1, gates do
		local frame = frameAt(startDist + raceLength * (k / gates))
		newPart("Part", ghost({
			Name = tostring(k),
			Size = Vector3.new(width + 24, 40, 2),
			CFrame = CFrame.lookAt(frame.Position, frame.Position + frame.LookVector),
			Transparency = 1,
		}), checkpointFolder)
	end

	-- Starting grid: rows of three behind the start line
	for k = 1, SETTINGS.MAX_RACERS do
		local row = math.floor((k - 1) / 3)
		local col = (k - 1) % 3
		local back = 12 + row * 12 + (if col == 1 then 5 else 0)
		local frame = frameAt(startDist - back)
		local slotCF = flatCFrame(frame.Position, frame.LookVector) * CFrame.new((col - 1) * 10, 0, 0)
		newPart("Part", ghost({
			Name = tostring(k),
			Size = Vector3.new(6, 0.1, 8),
			CFrame = slotCF,
			Transparency = 1,
		}), slotFolder)
		newPart("Part", ghost({
			Name = "GridMark",
			Size = Vector3.new(6, 0.1, 0.6),
			CFrame = slotCF * CFrame.new(0, 0.1, -4.5),
			Color = COLORS.White,
		}), decor)
	end

	track:SetAttribute("KillY", minY - 40) -- fall below this = respawn at last checkpoint
	track.Parent = workspace
	return track
end

------------------------------------------------------------------------
-- KART BUILDER
------------------------------------------------------------------------
-- How high the kart's centre floats above the road. At 1.1 the wheels just
-- touch it. The client reads this from the kart's "RideHeight" attribute.
local KART_RIDE_HEIGHT = 1.1

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
	kart:SetAttribute("RideHeight", KART_RIDE_HEIGHT)

	-- The invisible box that bumps into walls. It floats a little above the
	-- road (the client holds it up with raycast "springs"), so seams and slopes
	-- never scrape it. Zero friction because the client controls speed directly.
	local hitbox = Instance.new("Part")
	hitbox.Name = "Hitbox"
	hitbox.Size = Vector3.new(5.6, 1.2, 7.2)
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
-- LOBBY BUILDER
------------------------------------------------------------------------
local function buildLobby(): Folder
	local lobby = Instance.new("Folder")
	lobby.Name = "RaceLobby"
	local center = TRACK.ORIGIN + Vector3.new(-110, 0, 0)
	local radius = LOBBY.RADIUS

	local function spot(x: number, y: number, z: number): Vector3
		return center + Vector3.new(x, y, z)
	end
	local function facingCenter(x: number, y: number, z: number): CFrame
		local p = spot(x, y, z)
		return CFrame.lookAt(p, Vector3.new(center.X, p.Y, center.Z))
	end
	-- x/z of a spot on a circle around the middle. 0° = towards the track (east),
	-- 90° = south, 180° = west, 270° = north (where players face when they spawn).
	local function onRing(degrees: number, distance: number): (number, number)
		local a = math.rad(degrees)
		return math.cos(a) * distance, math.sin(a) * distance
	end
	local function disk(name: string, diameter: number, thickness: number, y: number, x: number?, z: number?): { [string]: any }
		return {
			Name = name,
			Shape = Enum.PartType.Cylinder,
			Size = Vector3.new(thickness, diameter, diameter),
			CFrame = upright(CFrame.new(spot(x or 0, y, z or 0))),
		}
	end

	-- The floating island: grassy top, rocky underside
	local floor = disk("Floor", radius * 2, 4, -2)
	floor.Color = COLORS.LobbyFloor
	floor.Material = Enum.Material.Grass
	newPart("Part", floor, lobby)
	local depth = -4
	for k, tier in { { 0.96, 4 }, { 0.78, 7 }, { 0.56, 8 }, { 0.34, 9 }, { 0.14, 9 } } do
		local rock = ghost(disk("IslandRock", radius * 2 * tier[1], tier[2], depth - tier[2] / 2))
		rock.Color = if k == 1 then COLORS.Dirt else COLORS.Rock
		rock.Material = if k == 1 then Enum.Material.Ground else Enum.Material.Slate
		newPart("Part", rock, lobby)
		depth -= tier[2]
	end

	-- Stone plaza with a gold ring around it
	local ring = disk("PlazaRing", 46, 0.3, 0)
	ring.Color = COLORS.Gold
	newPart("Part", ring, lobby)
	local plaza = disk("Plaza", 42, 0.4, 0.05)
	plaza.Color = COLORS.Plaza
	plaza.Material = Enum.Material.Pavement
	newPart("Part", plaza, lobby)

	local spawn = newPart("SpawnLocation", {
		Name = "LobbySpawn",
		Size = Vector3.new(12, 1, 12),
		CFrame = CFrame.new(spot(0, 0.75, 0)),
		Color = COLORS.White,
	}, lobby) :: SpawnLocation
	spawn.Neutral = true
	spawn.Duration = 0 -- no spawn force field

	-- See-through railing around the edge so nobody falls off
	local panels = 28
	for k = 0, panels - 1 do
		local x, z = onRing((k + 0.5) * 360 / panels, radius - 0.6)
		newPart("Part", {
			Name = "Railing",
			Size = Vector3.new(2 * math.pi * radius / panels + 0.2, 5, 0.6),
			CFrame = facingCenter(x, 2.5, z),
			Color = Color3.fromRGB(200, 230, 255),
			Material = Enum.Material.Glass,
			Transparency = 0.6,
		}, lobby)
		local px, pz = onRing(k * 360 / panels, radius - 0.6)
		local post = ghost(disk("RailPost", 0.9, 5.6, 2.8, px, pz))
		post.Color = COLORS.White
		newPart("Part", post, lobby)
	end

	-- Trees and lamp posts
	local rng = Random.new(11)
	for _, angle in { 25, 65, 115, 155, 205, 240, 300, 335 } do
		local x, z = onRing(angle, 46)
		buildTree(spot(x, 0, z), rng:NextNumber(0.9, 1.25), LEAF_COLORS[rng:NextInteger(1, #LEAF_COLORS)], lobby, true)
	end
	for k = 0, 7 do
		local x, z = onRing(22.5 + k * 45, 24)
		local pole = disk("LampPost", 0.6, 9, 4.5, x, z)
		pole.Color = COLORS.Dark
		newPart("Part", pole, lobby)
		newPart("Part", ghost({
			Name = "Lamp",
			Shape = Enum.PartType.Ball,
			Size = Vector3.one * 1.8,
			CFrame = CFrame.new(spot(x, 9.4, z)),
			Color = Color3.fromRGB(255, 240, 200),
			Material = Enum.Material.Neon,
		}), lobby)
	end

	-- Big status screen (north). The server updates the text as races come and go.
	local screen = newPart("Part", {
		Name = "StatusScreen",
		Size = Vector3.new(32, 12, 1),
		CFrame = facingCenter(0, 15, -49),
		Color = COLORS.Board,
	}, lobby)
	local screenGui = newSurfaceGui(screen, Enum.NormalId.Front, "Screen")
	newLabel({ Name = "Title", Size = UDim2.fromScale(0.94, 0.5), Position = UDim2.fromScale(0.03, 0.1), Text = "WELCOME TO KARTRACE!", TextColor3 = COLORS.Gold }, screenGui)
	newLabel({ Name = "Subtitle", Size = UDim2.fromScale(0.9, 0.24), Position = UDim2.fromScale(0.05, 0.64), Text = "" }, screenGui)
	for _, side in { -1, 1 } do
		newPart("Part", {
			Name = "ScreenLeg",
			Size = Vector3.new(1.5, 9, 1.5),
			CFrame = screen.CFrame * CFrame.new(side * 14, -10.5, 0.5),
			Color = COLORS.Dark,
		}, lobby)
	end
	for _, edge in { { 0, 6.3, 33.2, 0.6 }, { 0, -6.3, 33.2, 0.6 }, { 16.3, 0, 0.6, 12 }, { -16.3, 0, 0.6, 12 } } do
		newPart("Part", ghost({
			Name = "ScreenGlow",
			Size = Vector3.new(edge[3], edge[4], 1.2),
			CFrame = screen.CFrame * CFrame.new(edge[1], edge[2], 0),
			Color = COLORS.Wall,
			Material = Enum.Material.Neon,
		}), lobby)
	end

	-- Kart showroom: display karts slowly turning on pedestals (the client spins them)
	local showroom = newFolder("Showroom", lobby)
	for k, x in { -15, 0, 15 } do
		local color = KART_COLORS[k]
		local pedestal = disk("Pedestal", 10, 1.6, 0.8, x, -28)
		pedestal.Color = COLORS.Dark
		newPart("Part", pedestal, showroom)
		local glow = ghost(disk("PedestalGlow", 10.8, 0.4, 0.2, x, -28))
		glow.Color = color
		glow.Material = Enum.Material.Neon
		newPart("Part", glow, showroom)
		local kart, hitbox, seat = buildKart(color, CFrame.new(spot(x, 1.6 + KART_RIDE_HEIGHT, -28)) * CFrame.Angles(0, math.rad(k * 50), 0))
		seat:Destroy() -- just for looking at
		local align = hitbox:FindFirstChild("KartAlign")
		if align then
			align:Destroy()
		end
		kart.Name = "DisplayKart"
		kart:SetAttribute("Spin", LOBBY.SHOWROOM_SPIN * (if k % 2 == 0 then -1 else 1))
		kart.Parent = showroom
	end

	-- Podium showing the last race's top 3 (south-west)
	local px, pz = onRing(135, 31)
	local podiumCF = facingCenter(px, 0, pz)
	for place, info in { { x = 0, h = 4.5, color = COLORS.Gold }, { x = 6.4, h = 3, color = COLORS.Silver }, { x = -6.4, h = 2, color = COLORS.Bronze } } do
		local block = newPart("Part", {
			Name = "Podium" .. place,
			Size = Vector3.new(6, info.h, 6),
			CFrame = podiumCF * CFrame.new(info.x, info.h / 2, 0),
			Color = info.color,
		}, lobby)
		newLabel({ Size = UDim2.fromScale(1, 1), Text = tostring(place) }, newSurfaceGui(block, Enum.NormalId.Front))
		local nameBoard = newPart("Part", ghost({
			Name = "PodiumName" .. place,
			Size = Vector3.new(7, 1.6, 0.3),
			CFrame = podiumCF * CFrame.new(info.x, info.h + 6.5, 0),
			Color = COLORS.Board,
		}), lobby)
		newLabel({
			Name = "PlayerName",
			Size = UDim2.fromScale(0.94, 0.8),
			Position = UDim2.fromScale(0.03, 0.1),
			Text = "—",
			TextColor3 = info.color,
		}, newSurfaceGui(nameBoard, Enum.NormalId.Front, "NameGui"))
	end
	local header = newPart("Part", ghost({
		Name = "PodiumHeader",
		Size = Vector3.new(11, 2.2, 0.3),
		CFrame = podiumCF * CFrame.new(0, 14, 0),
		Color = COLORS.Board,
	}), lobby)
	newLabel({ Size = UDim2.fromScale(1, 1), Text = "LAST RACE", TextColor3 = COLORS.Gold }, newSurfaceGui(header, Enum.NormalId.Front))

	-- Bounce pads (the client launches you when you step on one)
	for k, angle in { 45, 315 } do
		local x, z = onRing(angle, 30)
		local pad = disk("BouncePad", 7, 0.6, 0.3, x, z)
		pad.Color = if k == 1 then Color3.fromRGB(80, 255, 140) else Color3.fromRGB(255, 90, 200)
		pad.Material = Enum.Material.Neon
		newPart("Part", pad, lobby):SetAttribute("BouncePower", LOBBY.BOUNCE_POWER)
		local padRing = ghost(disk("BouncePadRing", 8.6, 0.4, 0.2, x, z))
		padRing.Color = COLORS.White
		newPart("Part", padRing, lobby)
	end

	-- Global leaderboard board (west)
	local board = newPart("Part", {
		Name = "LeaderboardBoard",
		Size = Vector3.new(28, 18, 1),
		CFrame = facingCenter(-radius + 6, 13, 0),
		Color = COLORS.Board,
	}, lobby)
	for _, side in { -1, 1 } do
		newPart("Part", {
			Name = "BoardLeg",
			Size = Vector3.new(1.2, 4, 1.2),
			CFrame = board.CFrame * CFrame.new(side * 12, -11, 0.4),
			Color = COLORS.Dark,
		}, lobby)
	end
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

	-- How-to-play sign (south)
	local sign = newPart("Part", {
		Name = "HowToPlay",
		Size = Vector3.new(26, 13, 1),
		CFrame = facingCenter(0, 8.5, radius - 7),
		Color = COLORS.Board,
	}, lobby)
	for _, side in { -1, 1 } do
		newPart("Part", {
			Name = "SignLeg",
			Size = Vector3.new(1, 2, 1),
			CFrame = sign.CFrame * CFrame.new(side * 11, -7.5, 0.3),
			Color = COLORS.Dark,
		}, lobby)
	end
	local signGui = newSurfaceGui(sign, Enum.NormalId.Front)
	newLabel({ Size = UDim2.fromScale(1, 0.2), Text = "HOW TO PLAY", TextColor3 = COLORS.Gold }, signGui)
	newLabel({
		Size = UDim2.fromScale(0.9, 0.72),
		Position = UDim2.fromScale(0.05, 0.24),
		Text = "Races start automatically — just wait here!\n"
			.. "Orange pads give you a speed boost.\n"
			.. "Hold DRIFT while turning, let go for a mini-turbo.\n"
			.. "Fall off? You respawn at the last checkpoint.\n"
			.. "Waiting? Try the bounce pads!",
	}, signGui)

	lobby.Parent = workspace
	return lobby
end

------------------------------------------------------------------------
-- SCENERY  (sky, clouds and floating islands — just for looks)
------------------------------------------------------------------------
local function setupEnvironment()
	Lighting.GlobalShadows = true
	if not Lighting:FindFirstChildOfClass("Atmosphere") then
		local atmosphere = Instance.new("Atmosphere")
		atmosphere.Density = 0.3
		atmosphere.Offset = 0.25
		atmosphere.Color = Color3.fromRGB(199, 225, 255)
		atmosphere.Decay = Color3.fromRGB(104, 132, 170)
		atmosphere.Glare = 0.2
		atmosphere.Haze = 1.2
		atmosphere.Parent = Lighting
	end
	local terrain = workspace:FindFirstChildOfClass("Terrain")
	if terrain and not terrain:FindFirstChildOfClass("Clouds") then
		local clouds = Instance.new("Clouds")
		clouds.Cover = 0.6
		clouds.Density = 0.6
		clouds.Parent = terrain
	end
end

local function buildIsland(top: Vector3, radius: number, rng: Random, parent: Instance)
	newPart("Part", ghost({
		Name = "IslandGrass",
		Shape = Enum.PartType.Cylinder,
		Size = Vector3.new(3, radius * 2, radius * 2),
		CFrame = upright(CFrame.new(top - Vector3.new(0, 1.5, 0))),
		Color = COLORS.LobbyFloor,
		Material = Enum.Material.Grass,
	}), parent)
	local depth = 3
	for k, tier in { 0.92, 0.7, 0.45, 0.2 } do
		local thickness = radius * (if k == 1 then 0.15 else 0.3)
		newPart("Part", ghost({
			Name = "IslandRock",
			Shape = Enum.PartType.Cylinder,
			Size = Vector3.new(thickness, radius * 2 * tier, radius * 2 * tier),
			CFrame = upright(CFrame.new(top - Vector3.new(0, depth + thickness / 2, 0))),
			Color = if k == 1 then COLORS.Dirt else COLORS.Rock,
			Material = if k == 1 then Enum.Material.Ground else Enum.Material.Slate,
		}), parent)
		depth += thickness
	end
	for _ = 1, rng:NextInteger(1, 3) do
		local angle = rng:NextNumber(0, math.pi * 2)
		local offset = Vector3.new(math.cos(angle), 0, math.sin(angle)) * rng:NextNumber(0, radius * 0.55)
		buildTree(top + offset, rng:NextNumber(0.9, 1.6), LEAF_COLORS[rng:NextInteger(1, #LEAF_COLORS)], parent, false)
	end
end

local function buildScenery(): Folder
	local folder = Instance.new("Folder")
	folder.Name = "Scenery"
	local rng = Random.new(TRACK.SCENERY_SEED)

	local road: { Vector3 } = {}
	local minX, maxX, minZ, maxZ = math.huge, -math.huge, math.huge, -math.huge
	for i, p in (sampleTrack()) do
		road[i] = Vector3.new(p.X, 0, p.Z)
		minX, maxX = math.min(minX, p.X), math.max(maxX, p.X)
		minZ, maxZ = math.min(minZ, p.Z), math.max(maxZ, p.Z)
	end

	-- Things the islands must keep away from (the lobby counts as one)
	local lobbyCenter = TRACK.ORIGIN + Vector3.new(-110, 0, 0)
	local placed: { { pos: Vector3, radius: number } } = {
		{ pos = Vector3.new(lobbyCenter.X, 0, lobbyCenter.Z), radius = LOBBY.RADIUS + 30 },
	}
	local function isClear(pos: Vector3, radius: number): boolean
		for _, p in road do
			if (p - pos).Magnitude < radius + 60 then
				return false
			end
		end
		for _, other in placed do
			if (other.pos - pos).Magnitude < radius + other.radius + 25 then
				return false
			end
		end
		return true
	end

	local tries = 0
	while #placed < 22 and tries < 500 do
		tries += 1
		local radius = rng:NextNumber(14, 32)
		local flat = Vector3.new(rng:NextNumber(minX - 250, maxX + 250), 0, rng:NextNumber(minZ - 250, maxZ + 250))
		if isClear(flat, radius) then
			table.insert(placed, { pos = flat, radius = radius })
			buildIsland(flat + Vector3.new(0, TRACK.ORIGIN.Y + rng:NextNumber(-70, 25), 0), radius, rng, folder)
		end
	end

	folder.Parent = workspace
	return folder
end

------------------------------------------------------------------------
-- WORLD SETUP
------------------------------------------------------------------------
setupCollisionGroups()
setupEnvironment()

local trackFolder: Instance = workspace:FindFirstChild("RaceTrack") or buildTrack()
local lobbyFolder: Instance = workspace:FindFirstChild("RaceLobby") or buildLobby()
if not workspace:FindFirstChild("Scenery") then
	buildScenery()
end

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

-- Lights 1..lit glow in `color`, the rest go dark
local function setStartLights(lit: number, color: Color3)
	for k, light in sortedByNumber(trackFolder:FindFirstChild("StartLights")) do
		local on = k <= lit
		light.Color = if on then color else COLORS.LightOff
		light.Material = if on then Enum.Material.Neon else Enum.Material.SmoothPlastic
	end
end

-- Finds a TextLabel on one of the lobby's signs (nil if the sign isn't there)
local function lobbyLabel(partName: string, labelName: string): TextLabel?
	local part = lobbyFolder:FindFirstChild(partName)
	local gui = part and part:FindFirstChildWhichIsA("SurfaceGui")
	local label = gui and gui:FindFirstChild(labelName)
	return if label and label:IsA("TextLabel") then label else nil
end

local function updateLobbyScreen()
	local title = lobbyLabel("StatusScreen", "Title")
	local subtitle = lobbyLabel("StatusScreen", "Subtitle")
	if not (title and subtitle) then
		return
	end
	local phase = raceState:GetAttribute("Phase")
	if phase == "Intermission" then
		title.Text = string.format("NEXT RACE IN %d", tonumber(raceState:GetAttribute("Countdown")) or 0)
		subtitle.Text = "Stay on the island to join in!"
	elseif phase == "Countdown" then
		title.Text = "GET READY..."
		subtitle.Text = "The race is about to start!"
	elseif phase == "Racing" then
		title.Text = "RACE IN PROGRESS"
		subtitle.Text = string.format("%d racing — you're in the next one!", tonumber(raceState:GetAttribute("RacerCount")) or 0)
	elseif phase == "Results" then
		title.Text = "RACE OVER!"
		subtitle.Text = "Next race starting soon"
	else
		title.Text = "WAITING FOR PLAYERS"
		subtitle.Text = "Races start automatically"
	end
end
raceState:GetAttributeChangedSignal("Phase"):Connect(updateLobbyScreen)
raceState:GetAttributeChangedSignal("Countdown"):Connect(updateLobbyScreen)
updateLobbyScreen()

local function setPodium(results: { { name: string, place: number?, time: number? } })
	for place = 1, 3 do
		local label = lobbyLabel("PodiumName" .. place, "PlayerName")
		if label then
			local name = "—"
			for _, entry in results do
				if entry.place == place then
					name = entry.name
					break
				end
			end
			label.Text = name
		end
	end
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
	local kart, hitbox, seat = buildKart(color, slot.CFrame + Vector3.new(0, KART_RIDE_HEIGHT, 0))
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

	-- 2) Countdown (the start lights come on one by one)
	raceState:SetAttribute("Countdown", 0)
	setStartLights(0, COLORS.LightRed)
	setPhase("Countdown")
	task.wait(1)
	for n = SETTINGS.COUNTDOWN_TIME, 1, -1 do
		raceState:SetAttribute("Countdown", n)
		setStartLights(SETTINGS.COUNTDOWN_TIME - n + 1, COLORS.LightRed)
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
	setStartLights(SETTINGS.COUNTDOWN_TIME, COLORS.LightGreen)
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
	setPodium(results)
	setStartLights(0, COLORS.LightOff)
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
			setStartLights(0, COLORS.LightOff)
		end
	end
end
