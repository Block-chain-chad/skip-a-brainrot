-- Swings the player's arms FORWARD while a brainrot Tool is equipped, so the
-- creature (carried out in front by the server -- see InventoryHandler.buildHeld)
-- reads as being lugged along in both arms rather than floating on its own.
--
-- The pose is a runtime-registered KeyframeSequence, so no uploaded animation
-- asset is needed. Only the two upper arms are driven (Action priority); the
-- torso/root poses carry Weight 0 so walking and idle sway are left untouched.
local Players = game:GetService("Players")
local KeyframeSequenceProvider = game:GetService("KeyframeSequenceProvider")

local player = Players.LocalPlayer

-- Both arms swung forward to just below horizontal, as if bracing something
-- heavy against the body. 155 was the old overhead "holding it up" pose.
local ARM_PITCH = math.rad(72)

local function pose(name, cf, weight)
	local p = Instance.new("Pose")
	p.Name = name
	p.CFrame = cf or CFrame.new()
	p.Weight = weight or 1
	return p
end

-- One static hold pose. Two identical keyframes give the track a non-zero
-- length; a lone keyframe at t=0 evaluates to nothing and never applies.
local function buildHoldId()
	local function keyframe(t)
		local kf = Instance.new("Keyframe")
		kf.Time = t
		-- torso chain is only here to reach the arms in the rig hierarchy;
		-- Weight 0 means it does not override the running walk/idle animation
		local root  = pose("HumanoidRootPart", nil, 0)

		-- R15 chain
		local lower = pose("LowerTorso", nil, 0)
		local upper = pose("UpperTorso", nil, 0)
		upper:AddSubPose(pose("RightUpperArm", CFrame.Angles(ARM_PITCH, 0, 0)))
		upper:AddSubPose(pose("LeftUpperArm",  CFrame.Angles(ARM_PITCH, 0, 0)))
		lower:AddSubPose(upper)
		root:AddSubPose(lower)

		-- R6 chain. Poses for parts the active rig does not have are simply
		-- ignored, so carrying both costs nothing and means the carry works
		-- whichever rig the place is set to.
		local torso = pose("Torso", nil, 0)
		torso:AddSubPose(pose("Right Arm", CFrame.Angles(ARM_PITCH, 0, 0)))
		torso:AddSubPose(pose("Left Arm",  CFrame.Angles(ARM_PITCH, 0, 0)))
		root:AddSubPose(torso)

		kf:AddPose(root)
		return kf
	end
	local seq = Instance.new("KeyframeSequence")
	seq.Loop = true
	seq:AddKeyframe(keyframe(0))
	seq:AddKeyframe(keyframe(1))
	return KeyframeSequenceProvider:RegisterKeyframeSequence(seq)
end

local function brainrotEquipped(char)
	for _, c in ipairs(char:GetChildren()) do
		if c:IsA("Tool") and c:GetAttribute("BrainrotTool") then return true end
	end
	return false
end

local function setup(char)
	local humanoid = char:WaitForChild("Humanoid", 10)
	if not humanoid then return end
	local animator = humanoid:WaitForChild("Animator", 10)
	if not animator then return end

	local anim = Instance.new("Animation")
	anim.AnimationId = buildHoldId()
	local track = animator:LoadAnimation(anim)
	track.Priority = Enum.AnimationPriority.Action4
	track.Looped = true

	local function refresh()
		if brainrotEquipped(char) then
			if not track.IsPlaying then track:Play(0.15) end
		else
			if track.IsPlaying then track:Stop(0.15) end
		end
	end

	char.ChildAdded:Connect(function(c) if c:IsA("Tool") then refresh() end end)
	char.ChildRemoved:Connect(function(c) if c:IsA("Tool") then refresh() end end)
	refresh()
end

if player.Character then task.spawn(setup, player.Character) end
player.CharacterAdded:Connect(setup)
