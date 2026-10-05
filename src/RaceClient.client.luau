--[[
	RaceClient  —  a LocalScript that goes in StarterPlayer > StarterPlayerScripts

	Runs on each player's own device:
	  • arcade kart driving (gas, brake, steer, drift + mini-turbo, boost pads, jumps)
	    The kart floats just above the road on raycast "springs" instead of
	    scraping along it, which keeps it smooth over seams, hills and banked turns.
	  • chase camera
	  • race HUD: status bar, countdown, position, timer, results
	  • lobby fun: bounce pads and the spinning display karts

	The server (RaceServer) owns the rules: who races, checkpoints, finishing, wins.
	This script only drives *your* kart. The server hands your kart's physics to
	your device at GO, which is why steering feels instant instead of laggy.
]]

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ContextActionService = game:GetService("ContextActionService")
local UserInputService = game:GetService("UserInputService")
local TweenService = game:GetService("TweenService")

local player = Players.LocalPlayer
local raceState = ReplicatedStorage:WaitForChild("RaceState")
local raceEvent = ReplicatedStorage:WaitForChild("RaceEvent") :: RemoteEvent
local trackFolder = workspace:WaitForChild("RaceTrack")

------------------------------------------------------------------------
-- HANDLING  (tweak these to change how karts feel)
------------------------------------------------------------------------
local HANDLING = {
	MAX_SPEED = 80, -- studs per second (a walking character is 16)
	ACCELERATION = 40,
	BRAKE = 90,
	REVERSE_SPEED = 25,
	COAST_DECEL = 18, -- slow-down when you let go of the gas
	TURN_RATE = 2.4, -- radians per second at full steer
	GRIP = 10, -- how quickly sideways sliding dies out
	DRIFT_GRIP = 2.5,
	DRIFT_MIN_SPEED = 40,
	DRIFT_TURN = 1.15,
	DRIFT_BODY_ANGLE = 22, -- degrees the kart swings out while drifting (looks only)
	MINI_TURBO_1 = 0.8, -- seconds of drifting for a small boost (blue sparks)
	MINI_TURBO_2 = 1.7, -- seconds of drifting for a big boost (orange sparks)
	BOOST_SPEED = 115,
	PAD_BOOST_TIME = 1.2,
	AIR_GRAVITY = 0.55, -- fraction of normal gravity in the air (floatier jumps)
	AIR_STEER = 0.35,
	-- Suspension: the kart rides on invisible springs just above the road, so
	-- seams, hills and banked corners feel smooth instead of bumpy.
	HOVER_STIFFNESS = 14, -- how firmly the kart holds its ride height
	STICK_DISTANCE = 1.75, -- how far the road can drop away before the kart counts as airborne
	TILT_SPEED = 12, -- how quickly the kart leans to match slopes and banked corners
	WALL_BOUNCE = 0.3, -- how much karts bounce off walls (0 = not at all)
	WALL_SLIDE = 0.6, -- how much a wall hit turns the kart to slide along it (0 = none, 1 = fully)
}

-- Points under the kart (x = right, z = back) where it feels for the road,
-- so it tilts to the average of the surface instead of jolting at every seam.
local GROUND_PROBES = {
	Vector3.new(-1.8, 0, -2.4), -- front left
	Vector3.new(1.8, 0, -2.4), -- front right
	Vector3.new(-1.8, 0, 2.4), -- back left
	Vector3.new(1.8, 0, 2.4), -- back right
}
local WALL_HIT_MIN = 6 -- a sideways shove bigger than this (studs/s) in one frame counts as hitting a wall

local CAMERA = {
	DISTANCE = 17,
	HEIGHT = 6.5,
	LOOK_AHEAD = 10,
	SMOOTHING = 9,
	FOV = 70,
	BOOST_FOV = 84,
}

local SPARK_COLORS = {
	Color3.fromRGB(235, 235, 235), -- charging
	Color3.fromRGB(70, 170, 255), -- small boost ready
	Color3.fromRGB(255, 140, 30), -- big boost ready
}

local PLACE_COLORS = {
	Color3.fromRGB(255, 215, 70),
	Color3.fromRGB(210, 215, 225),
	Color3.fromRGB(225, 150, 90),
}
local WHITE = Color3.new(1, 1, 1)
local FONT = Enum.Font.FredokaOne

------------------------------------------------------------------------
-- Helpers
------------------------------------------------------------------------
-- Which way a direction points around the vertical axis (the kart's "heading")
local function headingOfDirection(dir: Vector3): number
	return math.atan2(-dir.X, -dir.Z)
end

local function headingOf(cf: CFrame): number
	return headingOfDirection(cf.LookVector)
end

-- Shortest signed difference between two angles, in radians
local function angleDiff(a: number, b: number): number
	return (a - b + math.pi) % (2 * math.pi) - math.pi
end

local function moveToward(value: number, target: number, step: number): number
	if value < target then
		return math.min(value + step, target)
	end
	return math.max(value - step, target)
end

local function ordinal(n: number): string
	local lastTwo = n % 100
	local last = n % 10
	if lastTwo < 11 or lastTwo > 13 then
		if last == 1 then
			return n .. "st"
		elseif last == 2 then
			return n .. "nd"
		elseif last == 3 then
			return n .. "rd"
		end
	end
	return n .. "th"
end

local function formatTime(seconds: number): string
	seconds = math.max(0, seconds)
	local minutes = math.floor(seconds / 60)
	return string.format("%d:%05.2f", minutes, seconds - minutes * 60)
end

local function formatClock(seconds: number): string
	local whole = math.max(0, math.ceil(seconds))
	return string.format("%d:%02d", math.floor(whole / 60), whole % 60)
end

local function numberAttr(instance: Instance, name: string): number
	local value = instance:GetAttribute(name)
	return if typeof(value) == "number" then value else 0
end

------------------------------------------------------------------------
-- HUD
------------------------------------------------------------------------
local gui = Instance.new("ScreenGui")
gui.Name = "RaceHUD"
gui.ResetOnSpawn = false
gui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
gui.Parent = player:WaitForChild("PlayerGui")

local function make(className: string, props: { [string]: any }, parent: Instance?): any
	local instance = Instance.new(className)
	for key, value in props do
		(instance :: any)[key] = value
	end
	if parent then
		instance.Parent = parent
	end
	return instance
end

local function textLabel(props: { [string]: any }, parent: Instance): TextLabel
	local defaults = {
		BackgroundTransparency = 1,
		Font = FONT,
		TextColor3 = WHITE,
		TextScaled = true,
		TextStrokeTransparency = 0.4,
		Text = "",
	}
	for key, value in props do
		defaults[key] = value
	end
	return make("TextLabel", defaults, parent)
end

local statusLabel = textLabel({
	Name = "Status",
	AnchorPoint = Vector2.new(0.5, 0),
	Position = UDim2.new(0.5, 0, 0, 8),
	Size = UDim2.new(0.5, 0, 0, 36),
	BackgroundColor3 = Color3.new(0, 0, 0),
	BackgroundTransparency = 0.45,
	TextStrokeTransparency = 1,
}, gui)
make("UICorner", { CornerRadius = UDim.new(0, 10) }, statusLabel)
make("UIPadding", { PaddingTop = UDim.new(0, 5), PaddingBottom = UDim.new(0, 5), PaddingLeft = UDim.new(0, 12), PaddingRight = UDim.new(0, 12) }, statusLabel)
make("UISizeConstraint", { MinSize = Vector2.new(240, 0), MaxSize = Vector2.new(520, 36) }, statusLabel)

local feedLabel = textLabel({
	Name = "Feed",
	AnchorPoint = Vector2.new(0.5, 0),
	Position = UDim2.new(0.5, 0, 0, 50),
	Size = UDim2.new(0.4, 0, 0, 24),
	TextTransparency = 1,
	TextStrokeTransparency = 1,
}, gui)

local placeLabel = textLabel({
	Name = "Place",
	Position = UDim2.new(0, 16, 0, 4),
	Size = UDim2.new(0, 150, 0, 78),
	TextXAlignment = Enum.TextXAlignment.Left,
	TextStrokeTransparency = 0,
	Visible = false,
}, gui)

local placeSubLabel = textLabel({
	Name = "PlaceOf",
	Position = UDim2.new(0, 18, 0, 80),
	Size = UDim2.new(0, 150, 0, 24),
	TextXAlignment = Enum.TextXAlignment.Left,
	Visible = false,
}, gui)

local timerLabel = textLabel({
	Name = "Timer",
	AnchorPoint = Vector2.new(1, 0),
	Position = UDim2.new(1, -16, 0, 8),
	Size = UDim2.new(0, 170, 0, 42),
	TextXAlignment = Enum.TextXAlignment.Right,
	Visible = false,
}, gui)

local bigLabel = textLabel({
	Name = "Big",
	AnchorPoint = Vector2.new(0.5, 0.5),
	Position = UDim2.fromScale(0.5, 0.38),
	Size = UDim2.fromScale(0.8, 0.2),
	TextTransparency = 1,
	TextStrokeTransparency = 1,
}, gui)

local hintLabel = textLabel({
	Name = "Hint",
	AnchorPoint = Vector2.new(0.5, 1),
	Position = UDim2.new(0.5, 0, 1, -14),
	Size = UDim2.new(0.6, 0, 0, 26),
	BackgroundColor3 = Color3.new(0, 0, 0),
	BackgroundTransparency = 0.5,
	TextStrokeTransparency = 1,
	Visible = false,
}, gui)
make("UICorner", { CornerRadius = UDim.new(0, 8) }, hintLabel)
make("UIPadding", { PaddingTop = UDim.new(0, 4), PaddingBottom = UDim.new(0, 4) }, hintLabel)

local resultsFrame = make("Frame", {
	Name = "Results",
	AnchorPoint = Vector2.new(0.5, 0.5),
	Position = UDim2.fromScale(0.5, 0.5),
	Size = UDim2.new(0, 360, 0, 0),
	AutomaticSize = Enum.AutomaticSize.Y,
	BackgroundColor3 = Color3.fromRGB(20, 20, 32),
	BackgroundTransparency = 0.12,
	Visible = false,
}, gui) :: Frame
make("UICorner", { CornerRadius = UDim.new(0, 14) }, resultsFrame)
make("UIPadding", { PaddingTop = UDim.new(0, 12), PaddingBottom = UDim.new(0, 12), PaddingLeft = UDim.new(0, 16), PaddingRight = UDim.new(0, 16) }, resultsFrame)
make("UIListLayout", { SortOrder = Enum.SortOrder.LayoutOrder, Padding = UDim.new(0, 4) }, resultsFrame)

local bigTween: Tween? = nil
local function showBig(text: string, color: Color3?, hold: number?)
	if bigTween then
		bigTween:Cancel()
	end
	bigLabel.Text = text
	bigLabel.TextColor3 = color or WHITE
	bigLabel.TextTransparency = 0
	bigLabel.TextStrokeTransparency = 0
	bigLabel.Size = UDim2.fromScale(0.9, 0.25)
	TweenService:Create(bigLabel, TweenInfo.new(0.18, Enum.EasingStyle.Back, Enum.EasingDirection.Out), { Size = UDim2.fromScale(0.8, 0.2) }):Play()
	local fade = TweenService:Create(
		bigLabel,
		TweenInfo.new(0.4, Enum.EasingStyle.Quad, Enum.EasingDirection.In, 0, false, hold or 0.6),
		{ TextTransparency = 1, TextStrokeTransparency = 1 }
	)
	bigTween = fade
	fade:Play()
end

local feedVersion = 0
local function showFeed(text: string)
	feedVersion += 1
	local version = feedVersion
	feedLabel.Text = text
	feedLabel.TextTransparency = 0
	feedLabel.TextStrokeTransparency = 0.4
	task.delay(3, function()
		if feedVersion == version then
			feedLabel.TextTransparency = 1
			feedLabel.TextStrokeTransparency = 1
		end
	end)
end

local hintVersion = 0
local function showHint()
	local text
	if UserInputService.TouchEnabled and not UserInputService.KeyboardEnabled then
		text = "Thumbstick: drive & steer  •  Hold DRIFT while turning  •  RESET: back to checkpoint"
	elseif UserInputService.GamepadEnabled and not UserInputService.KeyboardEnabled then
		text = "RT: gas  •  LT: brake  •  Stick: steer  •  Hold RB while turning: drift  •  Y: respawn"
	else
		text = "W/S: gas & brake  •  A/D: steer  •  Hold Space while turning: drift  •  R: respawn"
	end
	hintVersion += 1
	local version = hintVersion
	hintLabel.Text = text
	hintLabel.Visible = true
	task.delay(8, function()
		if hintVersion == version then
			hintLabel.Visible = false
		end
	end)
end

local resultsVersion = 0
local function showResults(list: { any })
	for _, child in resultsFrame:GetChildren() do
		if child:IsA("GuiObject") then
			child:Destroy()
		end
	end
	textLabel({ LayoutOrder = 0, Size = UDim2.new(1, 0, 0, 34), Text = "RACE RESULTS", TextColor3 = PLACE_COLORS[1] }, resultsFrame)
	for i, entry in list do
		if i > 12 then
			break
		end
		local row = make("Frame", { LayoutOrder = i, Size = UDim2.new(1, 0, 0, 24), BackgroundTransparency = 1 }, resultsFrame)
		local place = if typeof(entry.place) == "number" then entry.place else nil
		local color = if place then (PLACE_COLORS[place] or WHITE) else Color3.fromRGB(150, 150, 160)
		textLabel({ Size = UDim2.fromScale(0.18, 1), Text = if place then ordinal(place) else "DNF", TextColor3 = color, TextXAlignment = Enum.TextXAlignment.Left }, row)
		textLabel({ Position = UDim2.fromScale(0.2, 0), Size = UDim2.fromScale(0.52, 1), Text = tostring(entry.name), TextXAlignment = Enum.TextXAlignment.Left }, row)
		textLabel({
			Position = UDim2.fromScale(0.72, 0),
			Size = UDim2.fromScale(0.28, 1),
			Text = if typeof(entry.time) == "number" then formatTime(entry.time) else "—",
			TextColor3 = Color3.fromRGB(190, 190, 200),
			TextXAlignment = Enum.TextXAlignment.Right,
		}, row)
	end
	resultsFrame.Visible = true
	resultsVersion += 1
	local version = resultsVersion
	task.delay(7, function()
		if resultsVersion == version then
			resultsFrame.Visible = false
		end
	end)
end

------------------------------------------------------------------------
-- DRIVING
------------------------------------------------------------------------
type DriveState = {
	kart: Model,
	hitbox: BasePart,
	seat: VehicleSeat,
	align: AlignOrientation,
	humanoid: Humanoid,
	heading: number,
	boostTime: number,
	drifting: boolean,
	driftDir: number,
	driftTime: number,
	sparkTier: number,
	camPos: Vector3?,
	lastFallRequest: number,
	sparks: { ParticleEmitter },
	flame: ParticleEmitter?,
	effects: { Instance },
	rideHeight: number, -- how high the kart's centre floats above the road
	groundUp: Vector3, -- smoothed "up" of the road under the kart
	lastVelocity: Vector3?, -- the velocity we set last frame (to notice wall hits)
	wasGrounded: boolean,
	wallGrace: number, -- seconds before wall hits count (right after GO/respawn the server may still be moving the kart)
	shake: number, -- camera shake after a wall hit, fades to 0
}

local drive: DriveState? = nil
local driftHeld = false

-- Only the road surface counts as ground (not walls or decorations)
local rayParams = RaycastParams.new()
rayParams.FilterType = Enum.RaycastFilterType.Include
rayParams.FilterDescendantsInstances = { trackFolder:WaitForChild("Road", 5) or trackFolder }

-- Local-only particle effects (only you see your sparks in this MVP)
local function createEffects(hitbox: BasePart): ({ ParticleEmitter }, ParticleEmitter?, { Instance })
	local sparks: { ParticleEmitter } = {}
	local effects: { Instance } = {}
	for _, name in { "RearLeft", "RearRight" } do
		local attachment = hitbox:FindFirstChild(name)
		if attachment then
			local emitter = Instance.new("ParticleEmitter")
			emitter.Name = "DriftSparks"
			emitter.Rate = 70
			emitter.Lifetime = NumberRange.new(0.12, 0.25)
			emitter.Speed = NumberRange.new(8, 14)
			emitter.SpreadAngle = Vector2.new(35, 35)
			emitter.Size = NumberSequence.new(0.35, 0)
			emitter.LightEmission = 1
			emitter.EmissionDirection = Enum.NormalId.Back
			emitter.Enabled = false
			emitter.Parent = attachment
			table.insert(sparks, emitter)
			table.insert(effects, emitter)
		end
	end
	local flame: ParticleEmitter? = nil
	local exhaust = hitbox:FindFirstChild("Exhaust")
	if exhaust then
		local emitter = Instance.new("ParticleEmitter")
		emitter.Name = "BoostFlame"
		emitter.Texture = "rbxasset://textures/particles/fire_main.dds"
		emitter.Color = ColorSequence.new(Color3.fromRGB(255, 210, 90), Color3.fromRGB(255, 80, 20))
		emitter.Rate = 90
		emitter.Lifetime = NumberRange.new(0.15, 0.3)
		emitter.Speed = NumberRange.new(10, 16)
		emitter.Size = NumberSequence.new(1.1, 0.2)
		emitter.LightEmission = 1
		emitter.EmissionDirection = Enum.NormalId.Back
		emitter.Enabled = false
		emitter.Parent = exhaust
		flame = emitter
		table.insert(effects, emitter)
	end
	return sparks, flame, effects
end

type Ground = {
	normal: Vector3, -- which way is "up" on the road here
	distance: number, -- from the kart's centre down to the road
	boost: boolean, -- touching a boost pad?
}

-- Feels for the road under the kart. Returns nil when the kart is in the air.
local function senseGround(d: DriveState): Ground?
	local cf = d.hitbox.CFrame
	local down = -cf.UpVector
	local falling = math.max(0, d.hitbox.AssemblyLinearVelocity:Dot(down))
	-- look a bit further when dropping fast, so landings get caught in time
	local ray = down * (d.rideHeight + HANDLING.STICK_DISTANCE + falling * 0.05)

	local center = workspace:Raycast(cf.Position, ray, rayParams)
	local boost = center ~= nil and center.Instance:GetAttribute("BoostPad") == true
	local corners: { RaycastResult } = {}
	local cornerCount = 0
	for i, offset in GROUND_PROBES do
		local hit = workspace:Raycast(cf:PointToWorldSpace(offset), ray, rayParams)
		if hit then
			corners[i] = hit
			cornerCount += 1
			if hit.Instance:GetAttribute("BoostPad") then
				boost = true
			end
		end
	end

	-- All four corners over the road: use the plane through them. This averages
	-- out seams and creases, so the kart glides instead of twitching.
	if cornerCount == 4 then
		local fl, fr, bl, br = corners[1].Position, corners[2].Position, corners[3].Position, corners[4].Position
		local normal = (fr - bl):Cross(fl - br)
		if normal.Magnitude > 1e-3 then
			normal = normal.Unit
			if normal.Y < 0 then
				normal = -normal
			end
			if normal.Y > 0.5 then
				local middle = (fl + fr + bl + br) / 4
				return { normal = normal, distance = (cf.Position - middle):Dot(normal), boost = boost }
			end
		end
	end
	-- Otherwise (e.g. right at the lip of the jump) trust the middle ray alone
	if center and center.Normal.Y > 0.3 then
		return { normal = center.Normal, distance = (cf.Position - center.Position):Dot(center.Normal), boost = boost }
	end
	return nil
end

local function driveStep(dt: number)
	local d = drive
	if not d then
		return
	end
	local hitbox = d.hitbox

	-- Frozen on the grid during the countdown
	if hitbox.Anchored then
		d.heading = headingOf(hitbox.CFrame)
		d.boostTime = 0
		d.drifting = false
		d.lastVelocity = nil
		d.wallGrace = 0.5
		return
	end
	d.wallGrace = math.max(0, d.wallGrace - dt)

	local canDrive = raceState:GetAttribute("Phase") == "Racing" and player:GetAttribute("Finished") ~= true
	local throttle = if canDrive then d.seat.ThrottleFloat else 0
	local steer = if canDrive then d.seat.SteerFloat else 0

	-- What's under the kart?
	local ground = senseGround(d)
	local grounded = ground ~= nil
	if ground and ground.boost then
		d.boostTime = math.max(d.boostTime, HANDLING.PAD_BOOST_TIME)
	end
	-- Ease the kart's "up" toward the road's tilt (or back to level in the air)
	local targetUp = if ground then ground.normal else Vector3.yAxis
	d.groundUp = d.groundUp:Lerp(targetUp, 1 - math.exp(-HANDLING.TILT_SPEED * dt)).Unit
	local up = if grounded then d.groundUp else Vector3.yAxis
	local velocity = hitbox.AssemblyLinearVelocity

	-- Hit a wall? If something shoved the kart sideways since last frame, bounce
	-- off a little and turn to slide along the wall instead of grinding into it.
	if grounded and d.wasGrounded and d.lastVelocity and d.wallGrace <= 0 then
		local shove = velocity - d.lastVelocity
		shove -= up * shove:Dot(up) -- ignore up/down bumps
		if shove.Magnitude > WALL_HIT_MIN then
			local away = shove.Unit
			local look = CFrame.Angles(0, d.heading, 0).LookVector
			local into = look:Dot(away)
			if into < -0.05 then
				local along = look - away * into
				if along.Magnitude > 0.05 then
					d.heading += angleDiff(headingOfDirection(along), d.heading) * HANDLING.WALL_SLIDE
				end
			end
			velocity += away * math.min(shove.Magnitude * HANDLING.WALL_BOUNCE, 12)
			d.shake = math.clamp(shove.Magnitude / 40, 0.15, 1)
		end
	end

	-- Forward / right along the road surface
	local flatLook = CFrame.Angles(0, d.heading, 0).LookVector
	local forward = (flatLook - up * flatLook:Dot(up)).Unit
	local right = forward:Cross(up)
	local forwardSpeed = velocity:Dot(forward)
	local sideSpeed = velocity:Dot(right)
	local upSpeed = velocity:Dot(up)

	-- Drifting: hold the drift button while turning at speed.
	-- The longer you hold it, the bigger the boost when you let go.
	if d.drifting then
		if grounded then
			d.driftTime += dt
		end
		if not canDrive or forwardSpeed < HANDLING.DRIFT_MIN_SPEED * 0.6 then
			d.drifting = false -- lost too much speed (e.g. hit a wall): no boost
		elseif not driftHeld then
			if d.driftTime >= HANDLING.MINI_TURBO_2 then
				d.boostTime = math.max(d.boostTime, 1.1)
			elseif d.driftTime >= HANDLING.MINI_TURBO_1 then
				d.boostTime = math.max(d.boostTime, 0.6)
			end
			d.drifting = false
		end
	elseif driftHeld and canDrive and grounded and forwardSpeed > HANDLING.DRIFT_MIN_SPEED and math.abs(steer) > 0.3 then
		d.drifting = true
		d.driftDir = if steer > 0 then 1 else -1
		d.driftTime = 0
	end

	d.boostTime = math.max(0, d.boostTime - dt)
	local boosting = d.boostTime > 0

	-- Speed (only when wheels are on the ground)
	if grounded then
		if throttle > 0 then
			if forwardSpeed < 0 then
				forwardSpeed += HANDLING.BRAKE * dt
			else
				forwardSpeed += HANDLING.ACCELERATION * throttle * dt
			end
		elseif throttle < 0 then
			if forwardSpeed > 0 then
				forwardSpeed += HANDLING.BRAKE * throttle * dt
			else
				forwardSpeed += HANDLING.ACCELERATION * throttle * dt
			end
		else
			local decel = if canDrive then HANDLING.COAST_DECEL else HANDLING.BRAKE * 0.5
			forwardSpeed = moveToward(forwardSpeed, 0, decel * dt)
		end

		local topSpeed = if boosting then HANDLING.BOOST_SPEED else HANDLING.MAX_SPEED
		if boosting then
			forwardSpeed = math.max(forwardSpeed, HANDLING.BOOST_SPEED)
		end
		if forwardSpeed > topSpeed then
			forwardSpeed = math.max(topSpeed, forwardSpeed - 60 * dt) -- ease down after a boost
		end
		forwardSpeed = math.max(forwardSpeed, -HANDLING.REVERSE_SPEED)

		local grip = if d.drifting then HANDLING.DRIFT_GRIP else HANDLING.GRIP
		sideSpeed *= math.exp(-grip * dt)
	end

	-- Steering
	local turn
	if d.drifting then
		-- steering into the drift tightens it, steering out widens it
		turn = d.driftDir * (0.7 + 0.45 * steer * d.driftDir) * HANDLING.DRIFT_TURN
	else
		local speedFactor = math.clamp(math.abs(forwardSpeed) / 25, 0, 1)
		turn = steer * speedFactor * (if forwardSpeed < -1 then -1 else 1)
	end
	if not grounded then
		turn *= HANDLING.AIR_STEER
	end
	d.heading -= turn * HANDLING.TURN_RATE * dt

	-- Up/down: on the road, a spring holds the kart at its ride height (so it
	-- follows hills and banks smoothly). In the air, gravity is softened so
	-- jumps feel a bit floaty on purpose.
	if ground then
		upSpeed = math.clamp((d.rideHeight - ground.distance) * HANDLING.HOVER_STIFFNESS, -40, 40)
	else
		upSpeed += workspace.Gravity * (1 - HANDLING.AIR_GRAVITY) * dt
	end
	local newVelocity = forward * forwardSpeed + right * sideSpeed + up * upSpeed
	d.lastVelocity = newVelocity
	d.wasGrounded = grounded
	if grounded then
		-- cancel the gravity physics is about to add; the spring does the holding up
		newVelocity += Vector3.yAxis * (workspace.Gravity * dt)
	end
	hitbox.AssemblyLinearVelocity = newVelocity

	-- Point the kart along the heading, tilted to match the ground
	local tiltUp = d.groundUp
	local look = CFrame.Angles(0, d.heading, 0).LookVector
	local alongGround = look - tiltUp * look:Dot(tiltUp)
	if alongGround.Magnitude > 1e-3 then
		local target = CFrame.lookAt(Vector3.zero, alongGround.Unit, tiltUp)
		if d.drifting then
			target *= CFrame.Angles(0, -d.driftDir * math.rad(HANDLING.DRIFT_BODY_ANGLE), 0)
		end
		d.align.CFrame = target
	end

	-- Fell off the track?
	local killY = trackFolder:GetAttribute("KillY")
	if typeof(killY) == "number" and hitbox.Position.Y < killY and os.clock() - d.lastFallRequest > 1 then
		d.lastFallRequest = os.clock()
		raceEvent:FireServer("Respawn")
	end

	-- Effects
	local tier = 0
	if d.drifting then
		tier = if d.driftTime >= HANDLING.MINI_TURBO_2 then 3 elseif d.driftTime >= HANDLING.MINI_TURBO_1 then 2 else 1
	end
	if tier ~= d.sparkTier then
		d.sparkTier = tier
		for _, emitter in d.sparks do
			emitter.Enabled = tier > 0
			if tier > 0 then
				emitter.Color = ColorSequence.new(SPARK_COLORS[tier])
			end
		end
	end
	if d.flame then
		d.flame.Enabled = boosting
	end
end

local function cameraStep(dt: number)
	local d = drive
	if not d or not d.hitbox.Parent then
		return
	end
	local camera = workspace.CurrentCamera
	local pos = d.hitbox.Position
	local look = CFrame.Angles(0, d.heading, 0).LookVector
	local desired = pos - look * CAMERA.DISTANCE + Vector3.new(0, CAMERA.HEIGHT, 0)
	local previous = d.camPos
	local camPos: Vector3 = if previous then previous:Lerp(desired, 1 - math.exp(-CAMERA.SMOOTHING * dt)) else desired
	d.camPos = camPos
	local shake = Vector3.zero
	if d.shake > 0 then -- little rattle after bumping a wall
		d.shake = math.max(0, d.shake - dt * 3)
		shake = Vector3.new(math.random() - 0.5, math.random() - 0.5, math.random() - 0.5) * (d.shake * 1.2)
	end
	camera.CFrame = CFrame.lookAt(camPos + shake, pos + look * CAMERA.LOOK_AHEAD + Vector3.new(0, 2, 0))
	local targetFov = if d.boostTime > 0 then CAMERA.BOOST_FOV else CAMERA.FOV
	camera.FieldOfView += (targetFov - camera.FieldOfView) * (1 - math.exp(-6 * dt))
end

local function onDriftInput(_: string, inputState: Enum.UserInputState): Enum.ContextActionResult
	if inputState == Enum.UserInputState.Begin then
		driftHeld = true
	elseif inputState == Enum.UserInputState.End or inputState == Enum.UserInputState.Cancel then
		driftHeld = false
	end
	return Enum.ContextActionResult.Sink -- also stops Space from trying to jump
end

local function onRespawnInput(_: string, inputState: Enum.UserInputState): Enum.ContextActionResult
	if inputState == Enum.UserInputState.Begin then
		raceEvent:FireServer("Respawn")
	end
	return Enum.ContextActionResult.Sink
end

local function stopDriving()
	local d = drive
	if not d then
		return
	end
	drive = nil
	driftHeld = false
	ContextActionService:UnbindAction("KartDrift")
	ContextActionService:UnbindAction("KartRespawn")
	RunService:UnbindFromRenderStep("KartCamera")
	local camera = workspace.CurrentCamera
	camera.CameraType = Enum.CameraType.Custom
	camera.FieldOfView = CAMERA.FOV
	if d.humanoid.Parent then
		d.humanoid:SetStateEnabled(Enum.HumanoidStateType.Jumping, true)
		camera.CameraSubject = d.humanoid
	end
	for _, effect in d.effects do
		effect:Destroy()
	end
end

local function startDriving(seat: VehicleSeat, humanoid: Humanoid)
	if drive and drive.seat == seat then
		return
	end
	stopDriving()

	local kart = seat.Parent
	if not kart or not kart:IsA("Model") then
		return
	end
	local hitbox = (kart.PrimaryPart or kart:WaitForChild("Hitbox", 5)) :: BasePart?
	local align = if hitbox then hitbox:WaitForChild("KartAlign", 5) :: AlignOrientation? else nil
	if not hitbox or not align or humanoid.SeatPart ~= seat then
		return
	end

	local sparks, flame, effects = createEffects(hitbox)
	local rideHeight = kart:GetAttribute("RideHeight")
	drive = {
		kart = kart,
		hitbox = hitbox,
		seat = seat,
		align = align,
		humanoid = humanoid,
		heading = headingOf(hitbox.CFrame),
		boostTime = 0,
		drifting = false,
		driftDir = 1,
		driftTime = 0,
		sparkTier = 0,
		camPos = nil,
		lastFallRequest = 0,
		sparks = sparks,
		flame = flame,
		effects = effects,
		rideHeight = if typeof(rideHeight) == "number" then rideHeight else 1.1,
		groundUp = hitbox.CFrame.UpVector,
		lastVelocity = nil,
		wasGrounded = false,
		wallGrace = 0.5,
		shake = 0,
	}

	humanoid:SetStateEnabled(Enum.HumanoidStateType.Jumping, false)
	ContextActionService:BindActionAtPriority("KartDrift", onDriftInput, true, Enum.ContextActionPriority.High.Value, Enum.KeyCode.Space, Enum.KeyCode.LeftShift, Enum.KeyCode.ButtonR1)
	ContextActionService:SetTitle("KartDrift", "DRIFT")
	ContextActionService:BindAction("KartRespawn", onRespawnInput, true, Enum.KeyCode.R, Enum.KeyCode.ButtonY)
	ContextActionService:SetTitle("KartRespawn", "RESET")

	workspace.CurrentCamera.CameraType = Enum.CameraType.Scriptable
	RunService:BindToRenderStep("KartCamera", Enum.RenderPriority.Camera.Value + 1, cameraStep)
end

local function watchCharacter(character: Model)
	local humanoid = character:WaitForChild("Humanoid", 10) :: Humanoid?
	if not humanoid then
		return
	end
	local function update()
		local seat = humanoid.SeatPart
		if seat and seat:IsA("VehicleSeat") and seat:GetAttribute("KartSeat") then
			task.spawn(startDriving, seat, humanoid)
		elseif drive and drive.humanoid == humanoid then
			stopDriving()
		end
	end
	humanoid:GetPropertyChangedSignal("SeatPart"):Connect(update)
	update()
end

player.CharacterAdded:Connect(watchCharacter)
player.CharacterRemoving:Connect(stopDriving)
if player.Character then
	task.spawn(watchCharacter, player.Character)
end

-- Runs right before each physics step, so the velocity we set is exactly what gets simulated
RunService.PreSimulation:Connect(function(dt)
	local d = drive
	if d and not d.hitbox.Parent then
		stopDriving()
	elseif d then
		driveStep(dt)
	end
end)

-- Confetti burst from your kart when you cross the finish line (only you see it)
local function celebrate()
	local d = drive
	local attachment = d and d.hitbox:FindFirstChild("Center")
	if not attachment then
		return
	end
	local confetti = Instance.new("ParticleEmitter")
	confetti.Name = "Confetti"
	confetti.Color = ColorSequence.new({
		ColorSequenceKeypoint.new(0, Color3.fromRGB(255, 80, 80)),
		ColorSequenceKeypoint.new(0.25, Color3.fromRGB(255, 220, 60)),
		ColorSequenceKeypoint.new(0.5, Color3.fromRGB(80, 220, 120)),
		ColorSequenceKeypoint.new(0.75, Color3.fromRGB(70, 160, 255)),
		ColorSequenceKeypoint.new(1, Color3.fromRGB(220, 100, 255)),
	})
	confetti.Lifetime = NumberRange.new(1.2, 2)
	confetti.Speed = NumberRange.new(25, 45)
	confetti.SpreadAngle = Vector2.new(50, 50)
	confetti.EmissionDirection = Enum.NormalId.Top
	confetti.Acceleration = Vector3.new(0, -40, 0)
	confetti.Drag = 1.5
	confetti.Size = NumberSequence.new(0.5)
	confetti.Rotation = NumberRange.new(0, 360)
	confetti.RotSpeed = NumberRange.new(-200, 200)
	confetti.LightEmission = 0.3
	confetti.Rate = 0
	confetti.Parent = attachment
	confetti:Emit(80)
	task.delay(3, function()
		confetti:Destroy()
	end)
end

------------------------------------------------------------------------
-- RACE EVENTS
------------------------------------------------------------------------
local myFinishTime: number? = nil

raceState:GetAttributeChangedSignal("Phase"):Connect(function()
	local phase = raceState:GetAttribute("Phase")
	local racing = player:GetAttribute("Racing") == true
	if phase == "Countdown" then
		myFinishTime = nil
		resultsFrame.Visible = false
		if racing then
			showHint()
		end
	elseif phase == "Racing" and racing then
		showBig("GO!", Color3.fromRGB(90, 255, 120), 0.5)
	end
end)

raceState:GetAttributeChangedSignal("Countdown"):Connect(function()
	if raceState:GetAttribute("Phase") == "Countdown" and player:GetAttribute("Racing") == true then
		local n = numberAttr(raceState, "Countdown")
		if n > 0 then
			showBig(tostring(n), Color3.fromRGB(255, 230, 80), 0.4)
		end
	end
end)

raceEvent.OnClientEvent:Connect(function(action: string, ...)
	if action == "Respawned" then
		local cf = ...
		local d = drive
		if d and typeof(cf) == "CFrame" then
			d.kart:PivotTo(cf)
			d.hitbox.AssemblyLinearVelocity = Vector3.zero
			d.hitbox.AssemblyAngularVelocity = Vector3.zero
			d.heading = headingOf(cf)
			d.boostTime = 0
			d.drifting = false
			d.camPos = nil
			d.groundUp = Vector3.yAxis
			d.lastVelocity = nil
			d.wasGrounded = false
			d.wallGrace = 0.5
		end
	elseif action == "RacerFinished" then
		local userId, name, place, finishTime = ...
		if userId == player.UserId then
			myFinishTime = finishTime
			showBig("FINISH!  " .. ordinal(place), PLACE_COLORS[place] or WHITE, 1.6)
			celebrate()
		else
			showFeed(string.format("%s finished %s!", tostring(name), ordinal(place)))
		end
	elseif action == "TimeUp" then
		showBig("TIME'S UP!", Color3.fromRGB(255, 90, 90), 1.2)
	elseif action == "Results" then
		local list = ...
		if typeof(list) == "table" then
			showResults(list)
		end
	end
end)

------------------------------------------------------------------------
-- HUD UPDATE (every frame)
------------------------------------------------------------------------
RunService.RenderStepped:Connect(function()
	local phase = raceState:GetAttribute("Phase")
	local racing = player:GetAttribute("Racing") == true
	local finished = player:GetAttribute("Finished") == true
	local now = workspace:GetServerTimeNow()

	if phase == "Waiting" then
		statusLabel.Text = "Waiting for players..."
	elseif phase == "Intermission" then
		statusLabel.Text = string.format("Next race in %d", numberAttr(raceState, "Countdown"))
	elseif phase == "Countdown" then
		statusLabel.Text = if racing then "Get ready!" else "Race starting — you're in the next one!"
	elseif phase == "Racing" then
		local left = formatClock(numberAttr(raceState, "RaceEnd") - now)
		if racing and finished then
			statusLabel.Text = "Finished! Heading back to the lobby..."
		elseif racing then
			statusLabel.Text = "Time left: " .. left
		else
			statusLabel.Text = "Race in progress (" .. left .. " left) — you're in the next one!"
		end
	elseif phase == "Results" then
		statusLabel.Text = "Race over!"
	else
		statusLabel.Text = ""
	end

	local showRaceHud = racing and (phase == "Countdown" or phase == "Racing" or phase == "Results")
	timerLabel.Visible = showRaceHud
	placeLabel.Visible = showRaceHud
	placeSubLabel.Visible = showRaceHud
	if showRaceHud then
		if myFinishTime then
			timerLabel.Text = formatTime(myFinishTime)
		elseif phase == "Racing" then
			timerLabel.Text = formatTime(now - numberAttr(raceState, "RaceStart"))
		elseif phase == "Countdown" then
			timerLabel.Text = formatTime(0)
		end
		local place = numberAttr(player, "Place")
		if place > 0 then
			placeLabel.Text = ordinal(place)
			placeLabel.TextColor3 = PLACE_COLORS[place] or WHITE
		end
		placeSubLabel.Text = "of " .. numberAttr(raceState, "RacerCount")
	end
end)

------------------------------------------------------------------------
-- LOBBY (bounce pads, spinning display karts)
------------------------------------------------------------------------
local lastBounce = 0
local function hookBouncePad(pad: BasePart)
	pad.Touched:Connect(function(hit)
		local character = player.Character
		if not character or not hit:IsDescendantOf(character) or os.clock() - lastBounce < 0.5 then
			return
		end
		local humanoid = character:FindFirstChildOfClass("Humanoid")
		local root = character:FindFirstChild("HumanoidRootPart")
		local power = pad:GetAttribute("BouncePower")
		if not humanoid or humanoid.SeatPart or not root or not root:IsA("BasePart") or typeof(power) ~= "number" then
			return
		end
		lastBounce = os.clock()
		humanoid:ChangeState(Enum.HumanoidStateType.Freefall)
		local v = root.AssemblyLinearVelocity
		root.AssemblyLinearVelocity = Vector3.new(v.X, power, v.Z)
	end)
end

task.spawn(function()
	local lobby = workspace:WaitForChild("RaceLobby", 30)
	if not lobby then
		return
	end
	local spinners: { Model } = {}
	for _, item in lobby:GetDescendants() do
		if item:IsA("Model") and typeof(item:GetAttribute("Spin")) == "number" then
			table.insert(spinners, item)
		elseif item:IsA("BasePart") and item:GetAttribute("BouncePower") then
			hookBouncePad(item)
		end
	end
	-- Spinning them here (not on the server) keeps the motion perfectly smooth
	RunService.RenderStepped:Connect(function(dt)
		for _, model in spinners do
			local speed = model:GetAttribute("Spin")
			if model.Parent and typeof(speed) == "number" then
				model:PivotTo(model:GetPivot() * CFrame.Angles(0, math.rad(speed) * dt, 0))
			end
		end
	end)
end)
